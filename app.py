from __future__ import annotations

import json
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import rumps
from PyObjCTools import AppHelper

AUTH_FILE = Path.home() / ".codex" / "auth.json"
APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "CodexRateWatcher"
SAMPLES_FILE = APP_SUPPORT_DIR / "samples.json"
USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"


@dataclass
class AuthSnapshot:
  access_token: str
  account_id: str | None


@dataclass
class WindowUsage:
  used_percent: float
  limit_window_seconds: int
  reset_after_seconds: int
  reset_at: int

  @property
  def remaining_percent(self) -> float:
    return max(0.0, 100.0 - self.used_percent)

  @property
  def percent_label(self) -> str:
    return f"{round(self.used_percent):.0f}%"


@dataclass
class UsageLimit:
  allowed: bool
  limit_reached: bool
  primary_window: WindowUsage
  secondary_window: WindowUsage | None


@dataclass
class UsageSnapshot:
  plan_type: str
  rate_limit: UsageLimit
  code_review_rate_limit: UsageLimit
  credits: dict[str, Any]


@dataclass
class UsageSample:
  captured_at: float
  primary_used_percent: float
  primary_reset_at: int
  secondary_used_percent: float | None
  secondary_reset_at: int | None
  review_used_percent: float
  review_reset_at: int


@dataclass
class BurnEstimate:
  time_until_exhausted: float | None
  percent_per_hour: float | None
  status_text: str


class AuthStore:
  def load(self) -> AuthSnapshot:
    payload = json.loads(AUTH_FILE.read_text())
    tokens = payload.get("tokens") or {}
    access_token = tokens.get("access_token")
    if not access_token:
      raise RuntimeError("Could not find a valid access token in ~/.codex/auth.json.")
    return AuthSnapshot(access_token=access_token, account_id=tokens.get("account_id"))


class UsageAPIClient:
  def fetch(self, auth: AuthSnapshot) -> UsageSnapshot:
    request = urllib.request.Request(USAGE_URL)
    request.add_header("Authorization", f"Bearer {auth.access_token}")
    request.add_header("Accept", "application/json")
    request.add_header("User-Agent", "codex-rate-watcher/0.1")
    if auth.account_id:
      request.add_header("ChatGPT-Account-Id", auth.account_id)

    try:
      with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
      detail = error.read().decode("utf-8", errors="ignore").strip()
      raise RuntimeError(f"Usage API request failed with status {error.code}: {detail}") from error
    except urllib.error.URLError as error:
      raise RuntimeError(f"Network error while fetching usage: {error.reason}") from error

    return UsageSnapshot(
      plan_type=payload["plan_type"],
      rate_limit=self._parse_limit(payload["rate_limit"]),
      code_review_rate_limit=self._parse_limit(payload["code_review_rate_limit"]),
      credits=payload.get("credits") or {},
    )

  def _parse_limit(self, payload: dict[str, Any]) -> UsageLimit:
    secondary = payload.get("secondary_window")
    return UsageLimit(
      allowed=bool(payload["allowed"]),
      limit_reached=bool(payload["limit_reached"]),
      primary_window=self._parse_window(payload["primary_window"]),
      secondary_window=self._parse_window(secondary) if secondary else None,
    )

  def _parse_window(self, payload: dict[str, Any]) -> WindowUsage:
    return WindowUsage(
      used_percent=float(payload["used_percent"]),
      limit_window_seconds=int(payload["limit_window_seconds"]),
      reset_after_seconds=int(payload["reset_after_seconds"]),
      reset_at=int(payload["reset_at"]),
    )


class SampleStore:
  def load(self) -> list[UsageSample]:
    if not SAMPLES_FILE.exists():
      return []
    try:
      raw_items = json.loads(SAMPLES_FILE.read_text())
    except json.JSONDecodeError:
      return []
    samples: list[UsageSample] = []
    for item in raw_items:
      samples.append(
        UsageSample(
          captured_at=float(item["captured_at"]),
          primary_used_percent=float(item["primary_used_percent"]),
          primary_reset_at=int(item["primary_reset_at"]),
          secondary_used_percent=float(item["secondary_used_percent"]) if item.get("secondary_used_percent") is not None else None,
          secondary_reset_at=int(item["secondary_reset_at"]) if item.get("secondary_reset_at") is not None else None,
          review_used_percent=float(item["review_used_percent"]),
          review_reset_at=int(item["review_reset_at"]),
        )
      )
    return samples

  def append(self, snapshot: UsageSnapshot) -> list[UsageSample]:
    APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
    samples = self.load()
    samples.append(
      UsageSample(
        captured_at=time.time(),
        primary_used_percent=snapshot.rate_limit.primary_window.used_percent,
        primary_reset_at=snapshot.rate_limit.primary_window.reset_at,
        secondary_used_percent=snapshot.rate_limit.secondary_window.used_percent if snapshot.rate_limit.secondary_window else None,
        secondary_reset_at=snapshot.rate_limit.secondary_window.reset_at if snapshot.rate_limit.secondary_window else None,
        review_used_percent=snapshot.code_review_rate_limit.primary_window.used_percent,
        review_reset_at=snapshot.code_review_rate_limit.primary_window.reset_at,
      )
    )
    cutoff = time.time() - 10 * 24 * 60 * 60
    samples = [sample for sample in samples if sample.captured_at >= cutoff]
    SAMPLES_FILE.write_text(json.dumps([sample.__dict__ for sample in samples], indent=2))
    return samples


def condensed_duration(seconds: float) -> str:
  minutes = max(1, int(seconds // 60))
  days, remainder = divmod(minutes, 24 * 60)
  hours, mins = divmod(remainder, 60)
  if days:
    return f"{days}d {hours}h" if hours else f"{days}d"
  if hours:
    return f"{hours}h {mins}m" if mins else f"{hours}h"
  return f"{mins}m"


def reset_label(reset_at: int) -> str:
  reset_time = datetime.fromtimestamp(reset_at)
  now = datetime.now()
  if reset_time.date() == now.date():
    return reset_time.strftime("%H:%M")
  return reset_time.strftime("%d %b")


def estimate_burn(
  samples: list[UsageSample],
  current_window: WindowUsage,
  used_attr: str,
  reset_attr: str,
  horizon_seconds: int,
) -> BurnEstimate:
  same_window: list[UsageSample] = []
  for sample in samples:
    sample_reset = getattr(sample, reset_attr)
    sample_percent = getattr(sample, used_attr)
    if sample_reset is None or sample_percent is None:
      continue
    if int(sample_reset) == int(current_window.reset_at):
      same_window.append(sample)

  if not same_window:
    return BurnEstimate(None, None, "Need more samples to project a burn rate.")

  same_window.sort(key=lambda item: item.captured_at)
  cutoff = time.time() - horizon_seconds
  recent = [sample for sample in same_window if sample.captured_at >= cutoff] or same_window
  first = recent[0]
  last = recent[-1]
  elapsed = last.captured_at - first.captured_at
  if elapsed < 5 * 60:
    return BurnEstimate(None, None, "Collecting a few more minutes of data before estimating.")

  first_percent = getattr(first, used_attr)
  last_percent = getattr(last, used_attr)
  delta = float(last_percent) - float(first_percent)
  if delta <= 0.2:
    return BurnEstimate(None, 0.0, "Usage looks steady so far.")

  percent_per_hour = delta / elapsed * 3600.0
  if percent_per_hour <= 0:
    return BurnEstimate(None, None, "Usage looks steady so far.")

  time_until_exhausted = current_window.remaining_percent / percent_per_hour * 3600.0
  reset_remaining = current_window.reset_at - time.time()
  if 0 < reset_remaining < time_until_exhausted:
    return BurnEstimate(None, percent_per_hour, "At this pace the window resets before it fully drains.")

  return BurnEstimate(
    time_until_exhausted=time_until_exhausted,
    percent_per_hour=percent_per_hour,
    status_text=f"Burning about {percent_per_hour:.1f}% per hour.",
  )


class CodexRateWatcher(rumps.App):
  def __init__(self) -> None:
    super().__init__("Codex RL", icon=None, template=True, quit_button=None)
    self.auth_store = AuthStore()
    self.api_client = UsageAPIClient()
    self.sample_store = SampleStore()
    self.samples = self.sample_store.load()
    self.snapshot: UsageSnapshot | None = None
    self.error_message: str | None = None
    self.last_updated_at: datetime | None = None
    self.refresh_in_flight = False

    self.primary_item = rumps.MenuItem("5h      --      --")
    self.primary_burn_item = rumps.MenuItem("Collecting data...")
    self.weekly_item = rumps.MenuItem("Weekly   --      --")
    self.weekly_burn_item = rumps.MenuItem("Collecting data...")
    self.review_item = rumps.MenuItem("Code Review   --      --")
    self.review_burn_item = rumps.MenuItem("Collecting data...")
    self.updated_item = rumps.MenuItem("Updated: waiting for first sync")
    self.footer_item = rumps.MenuItem("Polling every minute")
    self.error_item = rumps.MenuItem("")
    self.error_item.hidden = True
    self.refresh_item = rumps.MenuItem("Refresh now", callback=self.refresh_clicked)
    self.quit_item = rumps.MenuItem("Quit", callback=self.quit_app)

    self.menu = [
      self.primary_item,
      self.primary_burn_item,
      None,
      self.weekly_item,
      self.weekly_burn_item,
      None,
      self.review_item,
      self.review_burn_item,
      None,
      self.updated_item,
      self.footer_item,
      self.error_item,
      None,
      self.refresh_item,
      self.quit_item,
    ]

    self.timer = rumps.Timer(self.on_timer, 60)
    self.timer.start()
    self.refresh()

  def on_timer(self, _: rumps.Timer) -> None:
    self.refresh()

  def refresh_clicked(self, _: rumps.MenuItem) -> None:
    self.refresh()

  def quit_app(self, _: rumps.MenuItem) -> None:
    rumps.quit_application()

  def refresh(self) -> None:
    if self.refresh_in_flight:
      return
    self.refresh_in_flight = True
    self.refresh_item.title = "Refreshing..."

    thread = threading.Thread(target=self._refresh_worker, daemon=True)
    thread.start()

  def _refresh_worker(self) -> None:
    try:
      auth = self.auth_store.load()
      snapshot = self.api_client.fetch(auth)
      samples = self.sample_store.append(snapshot)
      self.snapshot = snapshot
      self.samples = samples
      self.error_message = None
      self.last_updated_at = datetime.now()
    except Exception as error:  # noqa: BLE001
      self.error_message = str(error)
    finally:
      self.refresh_in_flight = False
      AppHelper.callAfter(self.render)

  def render(self) -> None:
    self.refresh_item.title = "Refresh now"

    if self.snapshot is None:
      self.title = "Codex RL"
      self.updated_item.title = "Updated: waiting for first sync"
      self.error_item.hidden = self.error_message is None
      self.error_item.title = self.error_message or ""
      return

    primary = self.snapshot.rate_limit.primary_window
    weekly = self.snapshot.rate_limit.secondary_window
    review = self.snapshot.code_review_rate_limit.primary_window

    primary_estimate = estimate_burn(self.samples, primary, "primary_used_percent", "primary_reset_at", 3 * 60 * 60)
    weekly_estimate = estimate_burn(self.samples, weekly, "secondary_used_percent", "secondary_reset_at", 3 * 24 * 60 * 60) if weekly else BurnEstimate(None, None, "Weekly window unavailable.")
    review_estimate = estimate_burn(self.samples, review, "review_used_percent", "review_reset_at", 3 * 24 * 60 * 60)

    self.title = f"{round(primary.used_percent):.0f}% RL"
    self.primary_item.title = f"5h      {condensed_duration(primary.reset_at - time.time())}      {primary.percent_label}   {reset_label(primary.reset_at)}"
    self.primary_burn_item.title = self._burn_title(primary_estimate)

    if weekly:
      self.weekly_item.title = f"Weekly   {condensed_duration(weekly.reset_at - time.time())}      {weekly.percent_label}   {reset_label(weekly.reset_at)}"
      self.weekly_burn_item.title = self._burn_title(weekly_estimate)
    else:
      self.weekly_item.title = "Weekly   unavailable"
      self.weekly_burn_item.title = "Weekly window unavailable."

    self.review_item.title = f"Code Review   {condensed_duration(review.reset_at - time.time())}      {review.percent_label}   {reset_label(review.reset_at)}"
    self.review_burn_item.title = self._burn_title(review_estimate)

    if self.last_updated_at:
      relative = self._relative_string(self.last_updated_at)
      self.updated_item.title = f"Updated: {relative}"

    if self.snapshot.credits.get("has_credits"):
      self.footer_item.title = "Credits available as fallback"
    else:
      self.footer_item.title = f"Plan: {self.snapshot.plan_type} | Polling every minute"

    self.error_item.hidden = self.error_message is None
    self.error_item.title = self.error_message or ""

  def _burn_title(self, estimate: BurnEstimate) -> str:
    if estimate.time_until_exhausted is not None:
      return f"At this pace: drains in {condensed_duration(estimate.time_until_exhausted)}"
    return estimate.status_text

  def _relative_string(self, timestamp: datetime) -> str:
    delta = datetime.now() - timestamp
    if delta < timedelta(seconds=90):
      return "just now"
    if delta < timedelta(hours=1):
      return f"{int(delta.total_seconds() // 60)}m ago"
    if delta < timedelta(days=1):
      return f"{int(delta.total_seconds() // 3600)}h ago"
    return timestamp.strftime("%Y-%m-%d %H:%M")


if __name__ == "__main__":
  CodexRateWatcher().run()

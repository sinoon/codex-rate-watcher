# Codex Token Cost Design

**Date:** 2026-04-01

**Status:** Approved for implementation

## Goal

Replace the current quota-derived cost estimate with a real token-cost model for
Codex by scanning local session logs, extracting token usage deltas, and pricing
those deltas by model. The same cost data must drive both the native app cost
dashboard and `codex-rate cost`.

## Non-Goals

- Do not keep the existing monthly-subscription heuristic as a visible cost
  metric.
- Do not add Claude or other provider support in this repository.
- Do not redesign the quota cards, recommendation logic, or account relay
  planner.
- Do not depend on a remote billing API for token cost.

## Problem

The current `CostTracker` estimates dollar value by spreading Plus or Team plan
price across quota percentages. That yields a rough "quota value" number, but it
does not reflect real token usage. `CodexBar` feels more accurate because it
parses local Codex session logs and multiplies token counts by model pricing.

Our repository already has access to the same raw material:

- `~/.codex/sessions/**/*.jsonl`
- managed account homes under
  `~/Library/Application Support/CodexRateWatcherNative/managed-codex-homes/*/sessions`
- `event_msg` rows with `payload.type == "token_count"`
- cumulative and per-step usage inside `info.total_token_usage` and
  `info.last_token_usage`

## Product Decision

Use a Codex-only local scanner inside `CodexRateKit` and retire the existing
quota-derived `CostTracker` outputs from user-facing surfaces.

The new visible cost semantics are:

- "Today" means token cost accumulated on the current calendar day from local
  session logs.
- "Last 30 days" means token cost accumulated over the rolling last 30 calendar
  days from local session logs.
- CLI `codex-rate cost` and the native cost card must use the same underlying
  snapshot structure and pricing table.

No fallback estimate should be shown when token pricing cannot be resolved for a
model. In that case:

- known token counts still appear when available
- cost values become unavailable for the affected scope
- the UI stays honest instead of silently reverting to the old heuristic

## Data Source

### Session roots

The scanner should read all of these roots:

1. Active Codex home:
   - `$CODEX_HOME/sessions` when `CODEX_HOME` is set
   - otherwise `~/.codex/sessions`
2. Archived sessions beside the active home when present:
   - `<codex-home>/archived_sessions`
3. Managed account homes created by this app:
   - `managed-codex-homes/*/sessions`
   - `managed-codex-homes/*/archived_sessions`

This ensures cost data survives account switching and includes sessions created
by accounts added through the managed-home flow.

### Log shape

Only parse JSONL rows where:

- `type == "event_msg"`
- `payload.type == "token_count"`

The scanner should also consume:

- `turn_context` to capture the current model when present
- `session_meta` to capture a stable session identifier for deduplication

For each `token_count` row, derive token deltas using:

1. `info.total_token_usage` when available by subtracting the previously seen
   cumulative totals in that file/session
2. otherwise `info.last_token_usage`

Use:

- `input_tokens`
- `cached_input_tokens` or `cache_read_input_tokens`
- `output_tokens`

Ignore `reasoning_output_tokens` for now because Codex pricing in practice is
already represented through input/output usage pricing, and the current upstream
data model does not need a separate visible line item.

## Deduplication And Incremental Scan Rules

The scanner must avoid double-counting when the same logical session is visible
from multiple paths or when files are rescanned.

Rules:

- Deduplicate by file identity when possible.
- Deduplicate by parsed `session_id` when available.
- Cache per-file metadata:
  - path
  - mtime
  - size
  - parsed bytes offset
  - last known model
  - last cumulative totals
  - session id
  - aggregated day/model token buckets
- When a file only grows, resume scanning from the previous parsed offset.
- When a file changes incompatibly or shrinks, rescan the full file and replace
  its cached contribution.

This keeps menu refreshes and CLI cost reads fast even when the local session
history becomes large.

## Pricing Model

Introduce a Codex-only pricing table in `CodexRateKit`.

Each pricing row contains:

- `inputCostPerToken`
- `outputCostPerToken`
- `cacheReadInputCostPerToken` when applicable
- optional display label for zero-price or preview models

The pricing function is:

`nonCachedInput * inputRate + cachedInput * cachedRate + output * outputRate`

Model normalization should:

- strip `openai/`
- fold dated suffixes like `-YYYY-MM-DD` to the base model when the base is
  known
- keep unknown models visible in breakdowns even if cost cannot be calculated

## Shared Runtime Model

Add a new token-cost model family in `CodexRateKit`.

Suggested shape:

- `TokenCostSnapshot`
- `TokenCostDailyEntry`
- `TokenCostModelBreakdown`
- `TokenCostSummary`
- `TokenCostScanner`
- `TokenCostCache`
- `TokenCostPricing`

The snapshot returned to callers should include:

- `todayTokens`
- `todayCostUSD`
- `last30DaysTokens`
- `last30DaysCostUSD`
- `daily` entries for the last 30 days
- `updatedAt`

Each daily entry should include:

- `date`
- `inputTokens`
- `cacheReadTokens`
- `outputTokens`
- `totalTokens`
- `costUSD`
- `modelsUsed`
- `modelBreakdowns`

## Integration Plan

### Shared library

Add the scanner and pricing logic to `Sources/CodexRateKit/`.

The existing `CostTracker` becomes obsolete for user-facing output and should be
removed from the call paths that render the cost dashboard. The old
quota-derived persistence file can remain unused or be removed if no longer
referenced after the refactor.

### Native app

`UsageMonitor.State.liveCost` should switch from `CostTracker.todaySummary(...)`
to a cached or freshly loaded `TokenCostSnapshot`.

`PopoverViewController` should render:

- today cost
- today tokens
- last 30 days cost
- last 30 days tokens

If detailed sparkline/projection values cannot be supported honestly from the
new scanner, those specific fields should be removed or replaced with simpler
summary rows instead of fabricating equivalents.

### CLI

`codex-rate cost` should stop reading `CostTracker.weeklyStats(...)` and instead
load the shared `TokenCostSnapshot`.

Text output should include:

- today cost and tokens
- last 30 days cost and tokens
- optional daily breakdown table for recent days

`--json` should expose the same token-cost snapshot shape used by the app.

### Raycast compatibility

The Raycast extension currently only calls `status` and `history`, so this
change does not require an immediate Raycast code change. The CLI JSON contract
for `cost` should still be designed cleanly for future extension use.

## Error Handling

Scanner failures should be non-fatal to the rest of the app.

Behavior:

- quota refresh still works even if token-cost scanning fails
- CLI `codex-rate cost` should surface a clear error
- native app cost card should display a compact unavailable/error state without
  breaking the rest of the popover

Common failure cases:

- sessions directory missing
- unreadable file
- malformed JSON lines
- unknown model pricing

Malformed lines should be skipped, not crash the scan.

## Testing Strategy

Add focused tests for:

- model normalization
- pricing math for cached and non-cached inputs
- total-based delta extraction
- fallback to last-token usage
- deduplication across duplicate session files
- rolling 30-day aggregation
- inclusion of managed account session roots
- CLI JSON/text rendering from a deterministic token-cost snapshot
- native state rendering when token-cost data exists and when it is unavailable

## Verification

Fresh verification should include:

1. targeted unit tests for the new token-cost core
2. full `swift test`
3. `swift run codex-rate cost --json`
4. release build through `./scripts/build_app.sh <version>`

The final implementation should let a user compare this repository's cost output
against local session logs without relying on monthly-subscription heuristics.

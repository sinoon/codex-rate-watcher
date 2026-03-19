<div align="center">

# ⚡ Codex Rate Watcher

### Never get throttled mid-session again.

A blazing-fast macOS menu bar app that monitors your [OpenAI Codex](https://openai.com/index/codex/) (ChatGPT Pro / Team) rate-limit usage in real time — with multi-account management, burn-rate predictions, and smart switching.

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-CN](https://img.shields.io/badge/lang-简体中文-red.svg)](README.zh-CN.md)
[![ja](https://img.shields.io/badge/lang-日本語-green.svg)](README.ja.md)
[![ko](https://img.shields.io/badge/lang-한국어-yellow.svg)](README.ko.md)
[![es](https://img.shields.io/badge/lang-Español-orange.svg)](README.es.md)
[![fr](https://img.shields.io/badge/lang-Français-purple.svg)](README.fr.md)
[![de](https://img.shields.io/badge/lang-Deutsch-black.svg)](README.de.md)

![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)
![Zero Dependencies](https://img.shields.io/badge/dependencies-zero-success)

<p>
  <img src="docs/screenshot.jpg" width="440" alt="Codex Rate Watcher — macOS menu bar app monitoring OpenAI Codex ChatGPT rate limits in real time" />
</p>

*Real-time quota monitoring · Burn-rate estimation · Multi-account switching · Reset countdown*

</div>

---

## 🤯 The Problem

You're deep in a flow state, pair-programming with Codex, refactoring a critical module — and suddenly **the rate limit wall hits**. No warning. No countdown. Just a cold `429 Too Many Requests`.

You wait. You refresh. You have no idea when your quota resets or how fast you burned through it.

**Codex Rate Watcher** fixes this. Permanently.

## 🎯 What It Does

Codex Rate Watcher lives in your macOS menu bar and gives you **total visibility** into your OpenAI Codex / ChatGPT rate-limit usage:

| Capability | Description |
|---|---|
| **📊 Real-time quota tracking** | Monitor 5-hour primary, weekly, and code review limits simultaneously |
| **🔥 Burn-rate estimation** | Predicts *exactly* when your quota runs out (e.g., "1h32min until exhausted, resets 14:30") |
| **⏰ Reset countdown** | Every quota card shows its reset time — not just when you're blocked |
| **👥 Multi-account profiles** | Auto-captures account snapshots; manage Plus & Team accounts side by side |
| **🧠 Smart switching** | Weighted scoring algorithm recommends the best account to switch to |
| **🔄 Auto-reconciliation** | Orphaned auth snapshots are auto-discovered and registered on startup |
| **🏷️ Plan badges** | Clearly labels Plus vs. Team in the UI |
| **🎨 Dark-themed UI** | Linear-inspired design with color-coded quota cards |

## ✨ Key Features

### 📊 Three-Dimensional Quota Tracking

Most developers only discover they've hit the rate limit *after* Codex stops responding. Codex Rate Watcher tracks **all three quota dimensions simultaneously** — the 5-hour primary window, the weekly aggregate window, and the code review limit — in a single glance from your menu bar.

### 🔥 Predictive Burn-Rate Engine

The built-in estimator uses **linear regression** over real usage samples to tell you *exactly* when each quota will run out. No guessing, no mental math — just a precise countdown like *"1h32min until exhausted, resets at 14:30"*.

### ⏰ Always-On Reset Countdown

Reset times aren't just for when you're blocked. **Every quota card always shows its reset time**, even when you're actively coding. You'll always know how much runway you have and when the next window opens.

### 👥 Multi-Account Management with Smart Switching

Managing multiple ChatGPT Pro or Team accounts? The app auto-captures authentication snapshots and scores each profile using a **weighted availability algorithm** (primary headroom × 3.2 + weekly × 0.45 + review × 0.08, with low-balance penalties). One click to switch — your current auth is auto-backed up.

### 🔄 Self-Healing Profile Store

The **orphaned snapshot reconciliation** engine scans your profile directory on startup, automatically discovers untracked auth snapshots, and registers them (deduplicated by SHA256 fingerprint). Even if the index file gets corrupted, your accounts are never lost.

### 🛡️ Privacy-First Architecture

All data stays on your machine. The app only communicates with the official ChatGPT Usage API (`chatgpt.com/backend-api/wham/usage`). No analytics, no telemetry, no third-party services. Your auth tokens never leave localhost.

### Additional Highlights

- **Menu bar status** — remaining percentage always visible at a glance
- **5-tier availability sorting** — usable → running low → blocked → error → unvalidated
- **Auth file watching** — detects `codex login` in real time via kqueue
- **Plan badges** — clearly shows Plus vs. Team in the primary card header
- **Debug window mode** — `--window` flag for standalone window (screenshots & debugging)
- **Zero dependencies** — pure Apple system frameworks, no third-party packages
- **Automated CI releases** — GitHub Actions builds universal `.app` bundles for both Apple Silicon and Intel on every tagged version

## 📥 Download

Pre-built `.app` bundles are available on the [Releases](https://github.com/sinoon/codex-rate-watcher/releases) page — **no Xcode or Swift toolchain required**.

| Chip | Download |
|---|---|
| **Apple Silicon** (M1 / M2 / M3 / M4) | [Latest release — Apple Silicon](https://github.com/sinoon/codex-rate-watcher/releases/latest) |
| **Intel** (x86_64) | [Latest release — Intel](https://github.com/sinoon/codex-rate-watcher/releases/latest) |

1. Download the `.zip` for your Mac's chip
2. Unzip and drag **Codex Rate Watcher.app** to `/Applications`
3. Launch — it appears in your menu bar (not the Dock)
4. Make sure Codex CLI is logged in (`~/.codex/auth.json` must exist)

> **First launch:** The app is not notarized. Right-click → **Open**, or go to System Settings → Privacy & Security → **Open Anyway**.

---

## 🚀 Build From Source

If you prefer to build it yourself:

### Prerequisites

- **macOS 14** (Sonoma) or later
- **Codex CLI** installed and logged in (`~/.codex/auth.json`)
- **Swift 6.2+** (Xcode 26 or [swift.org](https://swift.org) toolchain)

### Build & Run

```bash
# Clone
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher

# Run directly (debug mode)
swift run

# Or build a release .app bundle
swift build -c release
./scripts/build_app.sh 1.0.0
# → dist/Codex Rate Watcher.app
```

### Debug Window Mode

```bash
swift run CodexRateWatcherNative -- --window
```

Launches as a standalone window instead of a menu bar popover — great for screenshots & UI debugging.

## 🔬 How It Works

```
~/.codex/auth.json            ← Written by Codex CLI on login
        │
        ▼
   AuthStore (read token)
        │
        ▼
   UsageAPIClient ──────────► chatgpt.com/backend-api/wham/usage
        │
        ▼
   UsageMonitor (poll every 60s)
    │         │
    │         ▼
    │    SampleStore (persist samples)
    │         │
    │         ▼
    │    UsageEstimator (burn rate estimation)
    │
    ▼
   AuthProfileStore (multi-account management)
    │         │
    │         ▼
    │    AuthFileWatcher (detect account changes)
    │
    ▼
   AppDelegate (status bar) ◄──► PopoverViewController (GUI)
```

### Burn-Rate Estimation Engine

The estimator uses **linear regression** over time-series usage samples:

1. Filters samples within the current rate-limit window (matched by `reset_at`)
2. Selects recent samples (3h lookback for primary, 3d for weekly)
3. Computes `Δ usage / Δ time` → consumption rate per hour
4. Projects `remaining / rate` → time until exhaustion
5. If the window resets before exhaustion → "Won't run out before reset"

### Smart Account Scoring

```
score  = min(primary%, weekly%) × 3.2    // balanced availability (heaviest)
score += primary%                × 1.1    // 5h headroom
score += weekly%                 × 0.45   // weekly headroom
score += review%                 × 0.08   // code review headroom
if running_low: score -= 28               // penalty
if is_current:  score += 4                // stay bonus
```

The highest-scoring profile is recommended. Switching auto-backs up your current `auth.json`.

### Orphaned Snapshot Reconciliation

On startup, the app scans `auth-profiles/` for `.json` files not tracked in `profiles.json`. These orphaned snapshots are automatically registered (deduplicated by SHA256 fingerprint) — so you never lose an account even if the index gets out of sync.

## 📂 Data Storage

All data stays local. Nothing leaves your machine except calls to the official ChatGPT Usage API.

```
~/Library/Application Support/CodexRateWatcherNative/
├── samples.json         # Usage history (retained 10 days)
├── profiles.json        # Account profile index
├── auth-profiles/       # Saved auth.json snapshots (SHA256-fingerprinted)
└── auth-backups/        # Pre-switch auth.json backups
```

## 🏗️ Project Structure

```
codex-rate-watcher/
├── Package.swift                       # Swift Package Manager manifest
├── scripts/build_app.sh                # Build .app bundle
├── docs/screenshot.jpg                 # App screenshot
├── Sources/CodexRateWatcherNative/
│   ├── main.swift                      # Entry point (--window flag)
│   ├── AppDelegate.swift               # Status bar + popover / window
│   ├── Models.swift                    # Data models, reset formatting
│   ├── AuthStore.swift                 # Auth file I/O, JWT parsing
│   ├── AuthFileWatcher.swift           # kqueue file monitoring
│   ├── UsageAPIClient.swift            # ChatGPT Usage API client
│   ├── UsageMonitor.swift              # Core monitor + multi-account
│   ├── UsageEstimator.swift            # Burn-rate estimation
│   ├── Persistence.swift               # Storage, orphan reconciliation
│   └── PopoverViewController.swift     # AppKit GUI (dark theme)
├── LICENSE
└── README.md
```

## ⚙️ Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 6.2 |
| UI Framework | AppKit (code-only, no SwiftUI/XIB) |
| Build System | Swift Package Manager |
| Concurrency | Swift Concurrency (async/await, Actor) |
| Networking | URLSession |
| Crypto | CryptoKit (SHA256 fingerprinting) |
| File Watching | GCD DispatchSource (kqueue) |
| Dependencies | **None** — pure system frameworks |

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Open an issue for bugs or feature requests
- Submit a pull request
- Share your multi-account workflow tips

## 📄 License

[MIT](LICENSE) © 2026

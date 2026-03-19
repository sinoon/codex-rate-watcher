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

- **Menu bar status** — remaining percentage always visible at a glance
- **Three-dimensional tracking** — 5h primary window + weekly window + code review limits
- **Burn-rate predictions** — linear regression over usage samples to project exhaustion time
- **Reset time on every card** — "预计 1h32min 后耗尽，14:30 重置" even for active accounts
- **5-tier availability sorting** — usable → running low → blocked → error → unvalidated
- **One-click account switching** — auto-backup before swap
- **Auth file watching** — detects `codex login` in real time via kqueue
- **Orphaned snapshot reconciliation** — never lose a profile, even if the index breaks
- **Debug window mode** — `--window` flag for standalone window (screenshots & debugging)
- **Zero dependencies** — pure Apple system frameworks, no third-party packages

## 🚀 Quick Start

### Prerequisites

- **macOS 14** (Sonoma) or later
- **Codex CLI** installed and logged in (`~/.codex/auth.json`)
- **Swift 6.2+** (Xcode 26 or [swift.org](https://swift.org) toolchain)

### Install & Run

```bash
# Clone the repo
git clone https://github.com/sinoon/codex-rate-watcher.git
cd codex-rate-watcher

# Run directly
swift run

# Or build a release .app bundle
swift build -c release
./scripts/build_app.sh
# → dist/Codex Rate Watcher Native.app
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

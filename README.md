# Codex Rate Watcher

A macOS menu bar app that monitors your [OpenAI Codex](https://openai.com/index/codex/) (ChatGPT) API rate-limit usage in real time — with multi-account profile management and smart switching recommendations.

![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

<p align="center">
  <img src="docs/screenshot.jpg" width="420" alt="Codex Rate Watcher Screenshot" />
</p>

## Why?

If you use Codex (ChatGPT Pro/Team) heavily for coding, you've likely hit the frustrating moment where your rate limit runs out mid-session — with no warning. **Codex Rate Watcher** sits quietly in your menu bar and:

- Shows your remaining quota at a glance
- Tracks usage across **three dimensions**: 5-hour primary window, weekly window, and code review limits
- **Estimates** how fast you're burning through your quota and when it'll run out
- Shows **reset countdown** — always know exactly when your quota resets
- Manages **multiple accounts** so you can switch to a fresh one when needed
- **Recommends** the best account to switch to based on a weighted scoring algorithm
- **Auto-discovers** orphaned account snapshots and registers them at startup

## Features

- **Menu bar status** — percentage display always visible
- **5-hour primary rate limit** tracking with burn rate estimation and reset countdown
- **Weekly rate limit** tracking with reset time display
- **Code review rate limit** tracking
- **Burn rate estimation** — predicts when your quota will run out (e.g. "预计 1h32min 后耗尽，14:30 重置")
- **Reset time display** — every quota shows when it resets, not just when blocked
- **Plan badge** — clearly labels Plus / Team accounts in the primary card
- **Multi-account profile management** — auto-captures and stores account snapshots
- **Orphaned snapshot reconciliation** — auto-discovers auth snapshots not in the index and registers them
- **5-tier availability sorting** — profiles ranked by usable > running low > blocked > error > unvalidated
- **Smart switch recommendations** — weighted scoring to find the best account
- **auth.json file watching** — detects Codex CLI login changes in real time
- **One-click account switching** — with automatic backup
- **Dark-themed Popover GUI** — Linear-inspired design with color-coded quota cards
- **Debug window mode** — launch with `--window` for a standalone window (useful for screenshots & debugging)

## How It Works

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

### Burn Rate Estimation

The estimator collects usage samples over time and uses linear regression to project when your quota will be exhausted:

1. Filters samples belonging to the same rate-limit window (matched by `reset_at`)
2. Selects recent samples within a configurable lookback window (3h for primary, 3d for weekly)
3. Calculates `Δ usage / Δ time` → percent-per-hour consumption rate
4. Projects `remaining / rate` → estimated time until exhaustion
5. If the window resets before exhaustion → reports "Won't run out before reset"

### Smart Account Switching

The scoring algorithm evaluates each saved profile:

```
score  = min(primary%, weekly%) × 3.2    // balanced availability (heaviest weight)
score += primary%                × 1.1    // 5h headroom
score += weekly%                 × 0.45   // weekly headroom
score += review%                 × 0.08   // code review headroom
if running_low: score -= 28               // penalty
if is_current:  score += 4                // small bonus for staying
```

The profile with the highest score is recommended. When you switch, the current `auth.json` is automatically backed up.

### Orphaned Snapshot Reconciliation

On startup, the app scans the `auth-profiles/` directory for any `.json` files not tracked in `profiles.json`. These orphaned snapshots are automatically registered — deduplicated by SHA256 fingerprint — so you never lose an account even if the index gets out of sync.

## Prerequisites

- **macOS 14** (Sonoma) or later
- **Codex CLI** installed and logged in (creates `~/.codex/auth.json`)
- **Swift 6.2+** toolchain (Xcode 26 or [swift.org](https://swift.org) toolchain)

## Installation

### Build from source

```bash
swift build -c release
./scripts/build_app.sh
```

The built app bundle will be at `dist/Codex Rate Watcher Native.app`. Move it to `/Applications` if you'd like.

### Run directly

```bash
swift run
```

### Debug window mode

```bash
swift run CodexRateWatcherNative -- --window
```

This launches the app as a standalone window instead of a menu bar popover — useful for taking screenshots and debugging the UI.

## Usage

1. **Log in to Codex CLI** — this creates `~/.codex/auth.json`:
   ```bash
   codex login
   ```

2. **Launch the app** — a speedometer icon appears in your menu bar

3. **Click the icon** to see the popover:
   - Current account plan (Plus/Team) and status
   - Three rate-limit quota cards with percentages, burn estimates, and reset countdowns
   - Burn rate estimates (e.g. "预计 1h32min 后耗尽，14:30 重置")
   - Account switch recommendations

4. **Multi-account workflow**:
   - Log in with different Codex accounts — the app auto-captures each one
   - When your current account runs low, the app recommends the best alternative
   - Click "Switch" to swap `auth.json` instantly (with auto-backup)
   - Blocked accounts show their reset time (e.g. "周额度耗尽，3月22日 重置")

## Data Storage

All data is stored locally:

```
~/Library/Application Support/CodexRateWatcherNative/
├── samples.json         # Historical usage samples (retained 10 days)
├── profiles.json        # Account profile index
├── auth-profiles/       # Saved auth.json snapshots (SHA256-fingerprinted)
└── auth-backups/        # Pre-switch auth.json backups
```

No data is sent anywhere except the official ChatGPT Usage API (`chatgpt.com/backend-api/wham/usage`).

## Project Structure

```
codex-rate-watcher/
├── Package.swift                       # Swift Package Manager manifest
├── scripts/
│   └── build_app.sh                    # Build .app bundle
├── docs/
│   └── screenshot.jpg                  # App screenshot
├── Sources/CodexRateWatcherNative/
│   ├── main.swift                      # Entry point (supports --window flag)
│   ├── AppDelegate.swift               # Status bar + popover / window controller
│   ├── Models.swift                    # Data models, reset time formatting
│   ├── AuthStore.swift                 # Auth file read/write, JWT parsing
│   ├── AuthFileWatcher.swift           # File system monitoring (kqueue)
│   ├── UsageAPIClient.swift            # ChatGPT Usage API client
│   ├── UsageMonitor.swift              # Core monitor + multi-account logic
│   ├── UsageEstimator.swift            # Burn rate estimation
│   ├── Persistence.swift               # Sample & profile storage, orphan reconciliation
│   └── PopoverViewController.swift     # Full AppKit GUI (Linear-inspired dark theme)
├── LICENSE
└── README.md
```

## Tech Stack

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

## Contributing

Contributions are welcome! Feel free to:

- Open an issue for bugs or feature requests
- Submit a pull request
- Share your multi-account workflow tips

## License

[MIT](LICENSE) © 2026

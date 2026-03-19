# Codex Rate Watcher

A macOS menu bar app that monitors your [OpenAI Codex](https://openai.com/index/codex/) (ChatGPT) API rate-limit usage in real time — with multi-account profile management and smart switching recommendations.

![macOS](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![Python](https://img.shields.io/badge/Python-3.x-green)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

## Why?

If you use Codex (ChatGPT Pro/Team) heavily for coding, you've likely hit the frustrating moment where your rate limit runs out mid-session — with no warning. **Codex Rate Watcher** sits quietly in your menu bar and:

- Shows your remaining quota at a glance
- Tracks usage across **three dimensions**: 5-hour primary window, weekly window, and code review limits
- **Estimates** how fast you're burning through your quota and when it'll run out
- Manages **multiple accounts** so you can switch to a fresh one when needed
- **Recommends** the best account to switch to based on a weighted scoring algorithm

## Features

| Feature | Python Version | Native Version |
|---|:---:|:---:|
| Menu bar percentage display | ✅ | ✅ |
| 5-hour primary rate limit tracking | ✅ | ✅ |
| Weekly rate limit tracking | ✅ | ✅ |
| Code review rate limit tracking | ✅ | ✅ |
| Burn rate estimation | ✅ | ✅ |
| Auto-refresh (60s interval) | ✅ | ✅ |
| Multi-account profile management | — | ✅ |
| Smart switch recommendations | — | ✅ |
| auth.json file watching | — | ✅ |
| One-click account switching | — | ✅ |
| Popover GUI | — | ✅ |

## Screenshots

The native version features a dark-themed popover with two panels:

- **Left panel**: Current account status card, switch recommendation, and three quota cards (5h primary / weekly / code review) with color-coded progress (🟢 >60% / 🟡 26–60% / 🔴 <26%) and burn rate estimates
- **Right panel**: Saved account profiles list with status indicators and quick-switch buttons

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

### Smart Account Switching (Native)

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

## Prerequisites

- **macOS 14** (Sonoma) or later
- **Codex CLI** installed and logged in (creates `~/.codex/auth.json`)
- For the Python version: Python 3.x
- For the Native version: Swift 6.2+ toolchain (Xcode 26 or swift.org toolchain)

## Installation

### Option 1: Native Version (Recommended)

#### Build from source

```bash
cd native
swift build -c release
./scripts/build_app.sh
```

The built app bundle will be at `native/dist/Codex Rate Watcher Native.app`. Move it to `/Applications` if you'd like.

#### Run directly

```bash
cd native
swift run
```

### Option 2: Python Version

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run in development mode
./scripts/run_app.sh

# Or build as a standalone .app
./scripts/build_app.sh
# Output: dist/Codex Rate Watcher.app
```

## Usage

1. **Log in to Codex CLI** — this creates `~/.codex/auth.json`:
   ```bash
   codex login
   ```

2. **Launch the app** — a speedometer icon appears in your menu bar

3. **Click the icon** to see the popover (Native) or dropdown menu (Python):
   - Current account plan and status
   - Three rate-limit quota cards with percentages and reset countdowns
   - Burn rate estimates ("At this pace, runs out in ~2h 15m")
   - Account switch recommendations (Native)

4. **Multi-account workflow** (Native version):
   - Log in with different Codex accounts — the app auto-captures each one
   - When your current account runs low, the app recommends the best alternative
   - Click "Switch" to swap `auth.json` instantly (with auto-backup)

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
├── app.py                    # Python version — menu bar app (rumps)
├── requirements.txt          # Python dependencies
├── setup.py                  # py2app packaging config
├── scripts/
│   ├── build_app.sh          # Build Python .app bundle
│   └── run_app.sh            # Run Python version
├── native/                   # Swift native version
│   ├── Package.swift         # Swift Package Manager manifest
│   ├── scripts/
│   │   └── build_app.sh      # Build native .app bundle
│   └── Sources/CodexRateWatcherNative/
│       ├── main.swift                  # Entry point
│       ├── AppDelegate.swift           # Status bar + popover
│       ├── Models.swift                # Data models & types
│       ├── AuthStore.swift             # Auth file read/write
│       ├── AuthFileWatcher.swift       # File system monitoring
│       ├── UsageAPIClient.swift        # ChatGPT Usage API client
│       ├── UsageMonitor.swift          # Core monitor + multi-account
│       ├── UsageEstimator.swift        # Burn rate estimation
│       ├── Persistence.swift           # Sample & profile storage
│       └── PopoverViewController.swift # Full AppKit GUI
├── LICENSE
└── README.md
```

## Tech Stack

### Native Version

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

### Python Version

| Component | Technology |
|---|---|
| Language | Python 3 |
| UI Framework | [rumps](https://github.com/jaredks/rumps) (macOS menu bar) |
| Packaging | py2app |
| Networking | urllib (stdlib) |
| Threading | threading + PyObjCTools |

## Contributing

Contributions are welcome! Feel free to:

- Open an issue for bugs or feature requests
- Submit a pull request
- Share your multi-account workflow tips

## License

[MIT](LICENSE) © 2026

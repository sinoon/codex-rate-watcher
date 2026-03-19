# Codex Rate Watcher

Small macOS menu bar app that reads `~/.codex/auth.json`, polls the ChatGPT usage endpoint every minute, and estimates how quickly your current usage is burning down.

This build uses Python + `rumps` because the current machine's Swift GUI toolchain could not compile even the minimal AppKit sample reliably.

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Run During Development

```bash
./scripts/run_app.sh
```

## Build `.app`

```bash
./scripts/build_app.sh
```

The generated app bundle is written to:

```bash
./dist/Codex Rate Watcher.app
```

## Notes

- This app uses `https://chatgpt.com/backend-api/wham/usage`.
- It stores local sample history under `~/Library/Application Support/CodexRateWatcher/samples.json`.
- The ETA is based on recent observed `used_percent` changes inside the same reset window.
- Manual refresh is available from the menu.

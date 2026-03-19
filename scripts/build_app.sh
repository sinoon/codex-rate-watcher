#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex Rate Watcher Native"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_NAME="CodexRateWatcherNative"

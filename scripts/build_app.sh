#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv/bin/python"

cd "$ROOT_DIR"
rm -rf build dist
"$PYTHON_BIN" setup.py py2app
if [[ -d "$ROOT_DIR/dist/app.app" ]]; then
  mv "$ROOT_DIR/dist/app.app" "$ROOT_DIR/dist/Codex Rate Watcher.app"
fi
echo "Built $ROOT_DIR/dist/Codex Rate Watcher.app"

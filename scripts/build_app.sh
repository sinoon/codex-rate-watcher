#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." \&\& pwd)"
APP_NAME="Codex Rate Watcher"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_NAME="CodexRateWatcherNative"
VERSION="${1:-0.0.0}"

echo "Building Codex Rate Watcher v${VERSION}..."
ARCH="$(uname -m)"
echo "   Architecture: $ARCH"

if [[ ! -f "$ROOT_DIR/.build/release/$EXECUTABLE_NAME" ]]; then
  echo "   Building release..."
  cd "$ROOT_DIR"
  swift build -c release
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"


# Generate Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Codex Rate Watcher</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Rate Watcher</string>
  <key>CFBundleIdentifier</key>
  <string>com.sinoon.codex-rate-watcher</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleExecutable</key>
  <string>CodexRateWatcherNative</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built: $APP_DIR (v$VERSION)"

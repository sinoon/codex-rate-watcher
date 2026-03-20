#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex Rate Watcher"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
GUI_EXECUTABLE="CodexRateWatcherNative"
CLI_EXECUTABLE="codex-rate"
VERSION="${1:-0.0.0}"

echo "========================================"
echo " Building Codex Rate Watcher v${VERSION}"
echo "========================================"
ARCH="$(uname -m)"
echo "   Architecture: $ARCH"

# Build all targets (GUI + CLI)
echo ""
echo "-- Building release (all targets)..."
cd "$ROOT_DIR"
swift build -c release

BUILD_DIR="$ROOT_DIR/.build/release"

# Verify both binaries exist
if [[ ! -f "$BUILD_DIR/$GUI_EXECUTABLE" ]]; then
  echo "ERROR: GUI binary not found at $BUILD_DIR/$GUI_EXECUTABLE"
  exit 1
fi
if [[ ! -f "$BUILD_DIR/$CLI_EXECUTABLE" ]]; then
  echo "ERROR: CLI binary not found at $BUILD_DIR/$CLI_EXECUTABLE"
  exit 1
fi

# Package .app bundle
echo ""
echo "-- Packaging .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$GUI_EXECUTABLE" "$APP_DIR/Contents/MacOS/$GUI_EXECUTABLE"

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

# Copy CLI binary alongside .app
echo ""
echo "-- Copying CLI binary..."
cp "$BUILD_DIR/$CLI_EXECUTABLE" "$ROOT_DIR/dist/$CLI_EXECUTABLE"

# Summary
echo ""
echo "========================================"
echo " Build complete!"
echo "========================================"
echo "   .app  : $APP_DIR"
echo "   CLI   : $ROOT_DIR/dist/$CLI_EXECUTABLE"
echo "   Version: $VERSION"
echo ""
echo " dist/ contents:"
ls -lh "$ROOT_DIR/dist/"

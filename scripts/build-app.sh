#!/usr/bin/env bash
# Builds Noelify.app into ./build/ for local use.
#
#   scripts/build-app.sh            # release build
#   CONFIG=debug scripts/build-app.sh
#
# Requires macOS 13+ with Xcode 15+ (or the matching Command Line Tools).
# The app is ad-hoc signed for local use only; it is NOT notarized.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Noelify.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: Noelify.app can only be built on macOS." >&2
  exit 1
fi

echo "▸ Building Noelify ($CONFIG)…"
swift build -c "$CONFIG" --product Noelify
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Assembling $APP"
# Only ever removes our own build output.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Wallpapers"
cp "$BIN_DIR/Noelify" "$APP/Contents/MacOS/Noelify"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
find "$ROOT/Resources/Wallpapers" -maxdepth 1 -type f \( -name '*.png' -o -name '*.heic' -o -name '*.jpg' \) \
  -exec cp {} "$APP/Contents/Resources/Wallpapers/" \;
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
fi

echo "▸ Ad-hoc signing (local use only)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "✓ Built $APP"
echo "  Run it with:  open \"$APP\""

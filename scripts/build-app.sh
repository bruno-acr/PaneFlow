#!/bin/zsh
# Builds PaneFlow.app (Hardened Runtime) into ./build.
#   CONFIG=debug|release (default release)
#   PANEFLOW_SIGN_IDENTITY="Apple Development: …" for a stable signature. Without it the app is
#   signed ad-hoc and macOS forgets the Accessibility grant on every rebuild.
set -euo pipefail
ROOT="${0:A:h:h}"
CONFIG="${CONFIG:-release}"
# Build products must live outside iCloud-synced folders: File Provider adds extended attributes
# that codesign rejects ("resource fork, Finder information, or similar detritus not allowed").
SCRATCH="${PANEFLOW_SCRATCH:-$HOME/Library/Caches/PaneFlow/build}"
OUT="${PANEFLOW_OUT:-$HOME/Library/Caches/PaneFlow/app}"
IDENTITY="${PANEFLOW_SIGN_IDENTITY:--}"

swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG" --product PaneFlow
BIN="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)"

APP="$OUT/PaneFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PaneFlow" "$APP/Contents/MacOS/PaneFlow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"

codesign --force --options runtime --timestamp=none \
  --entitlements "$ROOT/Resources/PaneFlow.entitlements" \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

mkdir -p "$ROOT/build"
ln -sfn "$APP" "$ROOT/build/PaneFlow.app"
echo "Built $APP (identity: $IDENTITY, config: $CONFIG)"

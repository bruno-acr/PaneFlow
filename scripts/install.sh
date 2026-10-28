#!/bin/zsh
# Builds PaneFlow (release) and installs it to /Applications, replacing any previous copy.
# Note: with ad-hoc signing, replacing the app invalidates the Accessibility grant (re-grant after).
set -euo pipefail
ROOT="${0:A:h:h}"
DEST="${PANEFLOW_INSTALL_DIR:-/Applications}"
CONFIG=release "$ROOT/scripts/build-app.sh"
pkill -x PaneFlow 2>/dev/null || true
rm -rf "$DEST/PaneFlow.app"
ditto "$HOME/Library/Caches/PaneFlow/app/PaneFlow.app" "$DEST/PaneFlow.app"
codesign --verify --strict "$DEST/PaneFlow.app"
echo "Installed $DEST/PaneFlow.app"

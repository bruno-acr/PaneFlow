#!/bin/zsh
# Runs unit + integration tests with build products outside iCloud-synced folders.
set -euo pipefail
ROOT="${0:A:h:h}"
swift test --package-path "$ROOT" --scratch-path "${PANEFLOW_SCRATCH:-$HOME/Library/Caches/PaneFlow/build}" "$@"

#!/bin/zsh
# Runs the Phase 1 geometry self-test inside the bundled app (so that the app's own Accessibility
# grant is used) and prints the JSON report. Open Safari and Word (one window each) first.
#   --keep  leave the windows in the test layout instead of restoring them
set -euo pipefail
ROOT="${0:A:h:h}"
APP="/Applications/PaneFlow.app"; [[ -d "$APP" ]] || APP="$ROOT/build/PaneFlow.app"
REPORT="${TMPDIR:-/tmp}/paneflow-selftest.json"
rm -f "$REPORT"
EXTRA=()
[[ "${1:-}" == "--keep" ]] && EXTRA+=(--self-test-keep)
# `open` launches through LaunchServices: PaneFlow, not the terminal, is the responsible process for TCC.
open -n -W "$APP" --args --self-test --self-test-output "$REPORT" "${EXTRA[@]}"
cat "$REPORT"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print("\nRESULT:", "PASSED" if r["passed"] else "FAILED"); sys.exit(0 if r["passed"] else 1)' "$REPORT"

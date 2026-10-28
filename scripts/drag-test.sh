#!/bin/zsh
# End-to-end drag test: PaneFlow posts synthetic mouse events (do not touch the mouse for ~20 s).
# Needs Safari and Word open (one window each) and a Finder window will be opened on an empty temp folder.
# The resident PaneFlow is quit during the test (two instances would both react) and relaunched afterwards.
set -euo pipefail
ROOT="${0:A:h:h}"
APP="/Applications/PaneFlow.app"; [[ -d "$APP" ]] || APP="$ROOT/build/PaneFlow.app"
REPORT="${TMPDIR:-/tmp}/paneflow-dragtest.json"
rm -f "$REPORT"
WAS_RUNNING=0
if pgrep -xq PaneFlow; then WAS_RUNNING=1; pkill -x PaneFlow; sleep 1; fi
open -n -W "$APP" --args --drag-test --self-test-output "$REPORT"
[[ $WAS_RUNNING == 1 ]] && open "$APP"
cat "$REPORT"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print("\nRESULT:", "PASSED" if r["passed"] else "FAILED"); sys.exit(0 if r["passed"] else 1)' "$REPORT"

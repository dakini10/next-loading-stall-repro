#!/usr/bin/env bash
# Negative control: the same build with `loading.js` removed.
# If this is not 0, the repro is measuring something other than the boundary.
set -uo pipefail
cd "$(dirname "$0")"
RUNS="${1:-144}"; WORKERS="${2:-8}"; LOAD="${3:-2}"
mv "app/(app)/loading.jsx" "app/(app)/loading.jsx.off"
restore() { mv "app/(app)/loading.jsx.off" "app/(app)/loading.jsx" 2>/dev/null; }
trap restore EXIT
npx next build >/dev/null 2>&1 || { echo "build failed"; exit 2; }
pkill -f "next start -p 3210" 2>/dev/null; sleep 1
ITEM_COUNT="${ITEM_COUNT:-200}" BLURB_REPEAT="${BLURB_REPEAT:-6}" PAGE_DELAY_MS="${PAGE_DELAY_MS:-200}" \
  ./run-probe.sh no-loading "$RUNS" "$WORKERS" "$LOAD"
restore
npx next build >/dev/null 2>&1

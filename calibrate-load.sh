#!/usr/bin/env bash
# Find a synthetic-load level that puts 16.2.6 in a band where the stall actually
# shows. On a quiet machine the ambient contention is gone, so the load has to be
# supplied -- too little and every version reads 0, which would look like "fixed".
#
#   ./calibrate-load.sh [batch]
set -uo pipefail
cd "$(dirname "$0")"
BATCH="${1:-24}"
export ITEM_COUNT="${ITEM_COUNT:-200}" BLURB_REPEAT="${BLURB_REPEAT:-6}" PAGE_DELAY_MS="${PAGE_DELAY_MS:-200}"
dir="versions/16.2.6"
[ -d "$dir" ] || { echo "run ./setup-versions.sh first"; exit 2; }
for load in 0 2 4 8 12; do
  ( cd "$dir" && ./run-probe.sh "cal-load-$load" "$BATCH" 8 "$load" >/dev/null 2>&1 )
  s="$dir/tally/cal-load-$load.summary"
  lost=$(grep -o 'lost-wakeup(suspendedLanes=512)=[0-9]*' "$s" | cut -d= -f2)
  runs=$(grep -o 'observed=[0-9]*' "$s" | cut -d= -f2)
  after=$(grep -o 'loadavg_after=.*' "$s" | cut -d= -f2)
  echo "load_procs=$load  lost=$lost/$runs  loadavg_after=$after"
done
echo "Pick the lowest load that reproduces reliably; too high starves the run itself."

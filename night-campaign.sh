#!/usr/bin/env bash
# One command for the unattended night run: calibrate the synthetic load on the
# known-bad version, then measure all three versions interleaved at that level.
#
# Why calibrate first: on a quiet machine there is no ambient contention, and with
# too little load every version reads 0 -- which looks exactly like "fixed".
# 16.2.6 is the yardstick: if it does not stall, the run measured nothing.
set -uo pipefail
cd "$(dirname "$0")"
LOG="tally/night-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p tally
exec > >(tee -a "$LOG") 2>&1

echo "=== night campaign $(date '+%F %T') ==="
uptime

for v in 16.2.6 16.3.4 16.4.0-canary.19; do
  [ -d "versions/$v" ] || { echo "FATAL: versions/$v missing -- run ./setup-versions.sh"; exit 2; }
done

CAL_BATCH="${CAL_BATCH:-24}"
echo; echo "--- calibration on 16.2.6 (batch=$CAL_BATCH) ---"
BEST=""
for load in 2 4 8 12; do
  ( cd versions/16.2.6 && ./run-probe.sh "cal-$load" "$CAL_BATCH" 8 "$load" >/dev/null 2>&1 )
  s="versions/16.2.6/tally/cal-$load.summary"
  if [ ! -f "$s" ]; then echo "load=$load  NO SUMMARY"; continue; fi
  runs=$(sed -n 's/.*observed=\([0-9][0-9]*\).*/\1/p' "$s" | head -1)
  lost=$(sed -n 's/.*lost-wakeup(suspendedLanes=512)=\([0-9][0-9]*\).*/\1/p' "$s" | head -1)
  served=$(sed -n 's/.*next(served)=\([^ ]*\).*/\1/p' "$s" | head -1)
  echo "load=$load  served=$served  lost=$lost/$runs"
  # want a rate high enough that a batch of 24 can tell it apart from zero
  if [ "$runs" -gt 0 ] && [ "$lost" -ge 3 ] && [ -z "$BEST" ]; then BEST="$load"; fi
done

if [ -z "$BEST" ]; then
  echo "!! calibration never reproduced on 16.2.6. The campaign would measure nothing,"
  echo "!! so it is NOT being run. A zero here is a statement about the instrument,"
  echo "!! not about any next version."
  exit 3
fi
echo "chosen synthetic load: $BEST"

ROUNDS="${ROUNDS:-6}"; BATCH="${BATCH:-24}"
echo; echo "--- interleaved campaign: rounds=$ROUNDS batch=$BATCH load=$BEST ---"
./run-interleaved.sh "$ROUNDS" "$BATCH" 8 "$BEST"

echo; echo "--- totals (rows whose served version matched their label) ---"
awk -F, 'NR>1 && $2==$3 {runs[$2]+=$4; lost[$2]+=$5; slow[$2]+=$6}
         END {for (v in runs) printf "%-22s lost-wakeup %3d / %3d  = %5.2f%%  (slow/other %d)\n",
                v, lost[v], runs[v], (runs[v]?100*lost[v]/runs[v]:0), slow[v]}' tally/interleaved.csv | sort
echo
echo "discarded rows (served != label, or run lost):"
awk -F, 'NR>1 && ($2!=$3 || $4==0) {print "  " $0}' tally/interleaved.csv
echo "=== done $(date '+%F %T') ==="

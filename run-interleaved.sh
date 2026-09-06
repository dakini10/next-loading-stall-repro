#!/usr/bin/env bash
# Interleaved A/B/C campaign: every round measures all three versions back to back,
# under the same synthetic load, so a drift in machine conditions hits all three
# equally instead of being mistaken for a version difference.
#
#   ./run-interleaved.sh <rounds> <batch> <workers> <load-procs>
#
# Writes one CSV row per batch to tally/interleaved.csv:
#   round,version,served,runs,lost,slow,ok,load_before_1m,load_after_1m
set -uo pipefail
cd "$(dirname "$0")"

ROUNDS="${1:-6}"; BATCH="${2:-24}"; WORKERS="${3:-8}"; LOAD="${4:-4}"
export ITEM_COUNT="${ITEM_COUNT:-200}" BLURB_REPEAT="${BLURB_REPEAT:-6}" PAGE_DELAY_MS="${PAGE_DELAY_MS:-200}"

declare -a VERSIONS=("16.2.6" "16.3.4" "16.4.0-canary.19")
CSV="tally/interleaved.csv"
mkdir -p tally
[ -f "$CSV" ] || echo "round,version,served,runs,lost,slow,ok,load_before_1m,load_after_1m,started_at" > "$CSV"

load_1m() { uptime | sed -E 's/.*load averages?: //' | awk '{print $1}'; }

for ((r=1; r<=ROUNDS; r++)); do
  for ver in "${VERSIONS[@]}"; do
    dir="versions/$ver"
    [ -d "$dir" ] || { echo "missing $dir -- run ./setup-versions.sh first"; exit 2; }
    label="r${r}-${ver}"
    lb="$(load_1m)"
    started="$(date '+%Y-%m-%dT%H:%M:%S')"
    ( cd "$dir" && ./run-probe.sh "$label" "$BATCH" "$WORKERS" "$LOAD" >/dev/null 2>&1 )
    s="$dir/tally/${label}.summary"
    if [ ! -f "$s" ]; then
      echo "$r,$ver,MISSING,0,0,0,0,$lb,$(load_1m),$started" >> "$CSV"
      echo "[round $r] $ver -- NO SUMMARY (run was lost)"
      continue
    fi
    served=$(sed -n 's/.*next(served)=\([^ ]*\).*/\1/p' "$s" | head -1)
    runs=$(sed -n 's/.*observed=\([0-9][0-9]*\).*/\1/p' "$s" | head -1)
    ok=$(sed -n 's/.*  ok=\([0-9][0-9]*\).*/\1/p' "$s" | head -1)
    lost=$(sed -n 's/.*lost-wakeup(suspendedLanes=512)=\([0-9][0-9]*\).*/\1/p' "$s" | head -1)
    slow=$(sed -n 's/.*slow-or-other=\([0-9][0-9]*\).*/\1/p' "$s" | head -1)
    la="$(load_1m)"
    echo "$r,$ver,$served,$runs,$lost,$slow,$ok,$lb,$la,$started" >> "$CSV"
    echo "[round $r] $ver served=$served runs=$runs lost=$lost slow=$slow load ${lb}->${la}"
    # A batch whose served version does not match its label is not evidence.
    if [ "$served" != "$ver" ]; then
      echo "  WARNING: served=$served but label says $ver -- discard this row"
    fi
  done
done
echo "csv: $CSV"

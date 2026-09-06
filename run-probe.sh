#!/usr/bin/env bash
# Tally STALL vs ok over N runs, under a controlled synthetic CPU load.
#
#   ./run-probe.sh <label> <runs> <workers> <load-procs>
#
# Exit code is not a verdict: this measures, it does not judge.
set -uo pipefail
LABEL="${1:?label}"; RUNS="${2:-24}"; WORKERS="${3:-8}"; LOAD="${4:-2}"
cd "$(dirname "$0")"

OUT="tally/${LABEL}.log"
mkdir -p tally

NEXT_VER="$(node -e 'console.log(require("next/package.json").version)')"
REACT_VER="$(node -e 'try{const p=require("next/dist/compiled/react-dom/package.json");console.log(p.version)}catch(e){console.log("?")}' 2>/dev/null)"
LOAD_BEFORE="$(uptime | sed -E "s/.*load averages?: //")"

pids=()
for ((i=0;i<LOAD;i++)); do yes >/dev/null & pids+=($!); done
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

RUNS="$RUNS" WORKERS="$WORKERS" MODE="${MODE:-plain}" PROBE_PATH="${PROBE_PATH:-/decks}" EXPECT_NEXT="$NEXT_VER" npx playwright test 2>&1 | tee "$OUT" >/dev/null
cleanup; pids=()

OK=$(grep -c '\[PROBE\].* ok ' "$OUT")
STALL=$(grep -c '\[PROBE\].* STALL ' "$OUT")
SEEN=$((OK+STALL))
# A run that missed the window because the machine was overloaded is NOT a lost
# wakeup. Split them: the bug leaves a suspended transition lane behind
# (suspendedLanes=512, pingedLanes=0); a merely slow run ends with lanes at 0.
LOST=$(grep ' STALL ' "$OUT" | grep -c '"suspendedLanes":512')
SLOW=$((STALL-LOST))
LOAD_AFTER="$(uptime | sed -E "s/.*load averages?: //")"

{
  echo "label=$LABEL next(installed)=$NEXT_VER next(served)=$(grep -o "next=[0-9][^ ]*" "$OUT" | head -1 | cut -d= -f2)"
  echo "mode=${MODE:-plain} page_delay_ms=${PAGE_DELAY_MS:-120} inner_suspense=${INNER_SUSPENSE:-0}"
  echo "runs_requested=$RUNS workers=$WORKERS synthetic_load_procs=$LOAD"
  echo "observed=$SEEN  STALL=$STALL  ok=$OK"
  echo "  of which lost-wakeup(suspendedLanes=512)=$LOST  slow-or-other=$SLOW"
  echo "loadavg_before=$LOAD_BEFORE"
  echo "loadavg_after=$LOAD_AFTER"
} | tee "tally/${LABEL}.summary"

if [ "$SEEN" -ne "$RUNS" ]; then
  echo "WARNING: observed($SEEN) != requested($RUNS) -- runs were lost, not 'ok'." | tee -a "tally/${LABEL}.summary"
fi

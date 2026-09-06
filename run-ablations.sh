#!/usr/bin/env bash
# Remove one ingredient at a time and re-measure, so the report can say which of
# them the failure actually needs. Run on 16.2.6, where the signal is ~22% and
# n=48 is enough to tell 22% apart from 0.
#
#   npm install next@16.2.6 && npx next build && ./run-ablations.sh [runs]
set -uo pipefail
cd "$(dirname "$0")"
RUNS="${1:-48}"
A="app/(app)"
export ITEM_COUNT="${ITEM_COUNT:-200}" BLURB_REPEAT="${BLURB_REPEAT:-6}" PAGE_DELAY_MS="${PAGE_DELAY_MS:-200}"

run() {  # run <label> [extra env assignments already exported by caller]
  local label="$1"
  npx next build >/dev/null 2>&1 || { echo "[$label] BUILD FAILED"; return 2; }
  pkill -f "next start -p 3210" 2>/dev/null; sleep 1
  ./run-probe.sh "$label" "$RUNS" 8 2 >/dev/null 2>&1
  sed -n '1,5p' "tally/${label}.summary"
  echo
}

restore() {
  [ -f "$A/loading.jsx.off" ] && mv "$A/loading.jsx.off" "$A/loading.jsx"
  [ -f "$A/layout.async.bak" ] && mv "$A/layout.async.bak" "$A/layout.jsx"
  if [ -f "$A/page.moved.bak" ]; then
    mv "$A/page.jsx" "$A/decks/page.jsx" 2>/dev/null
    mv "$A/page.moved.bak" "$A/page.jsx"
    python3 -c "import os;p=os.path.join('$A','decks','page.jsx');s=open(p).read().replace('from \"./Item\"','from \"../Item\"').replace('from \"./actions\"','from \"../actions\"');open(p,'w').write(s)"
  fi
  return 0
}
trap restore EXIT

# 0) control for this batch: the full shape
run "abl-0-full"

# 1) drop loading.js
mv "$A/loading.jsx" "$A/loading.jsx.off"
run "abl-1-no-loading"
mv "$A/loading.jsx.off" "$A/loading.jsx"

# 2) put the page in the boundary's own segment instead of one below it
mv "$A/page.jsx" "$A/page.moved.bak"          # park the redirect page
mv "$A/decks/page.jsx" "$A/page.jsx"
python3 -c "import os;p=os.path.join('$A','page.jsx');s=open(p).read().replace('from \"../Item\"','from \"./Item\"').replace('from \"../actions\"','from \"./actions\"');open(p,'w').write(s)"
PROBE_PATH=/ run "abl-2-page-at-boundary"
python3 -c "import os;p=os.path.join('$A','page.jsx');s=open(p).read().replace('from \"./Item\"','from \"../Item\"').replace('from \"./actions\"','from \"../actions\"');open(p,'w').write(s)"
mv "$A/page.jsx" "$A/decks/page.jsx"
mv "$A/page.moved.bak" "$A/page.jsx"

# 3) make the layout synchronous
mv "$A/layout.jsx" "$A/layout.async.bak"
cp "$A/layout.sync.alt" "$A/layout.jsx"
run "abl-3-sync-layout"
mv "$A/layout.async.bak" "$A/layout.jsx"

echo "done"

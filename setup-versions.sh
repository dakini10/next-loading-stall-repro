#!/usr/bin/env bash
# Stand up one installed+built copy of the app per next version, each on its own
# port, so a campaign can interleave versions without paying an install per switch.
#
# Interleaving is the point: the stall rate moves with machine load, so versions
# measured hours apart are not comparable. Same round, same conditions.
set -uo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

declare -a VERSIONS=("16.2.6:3221" "16.3.4:3222" "16.4.0-canary.19:3223")

for entry in "${VERSIONS[@]}"; do
  ver="${entry%%:*}"; port="${entry##*:}"
  dir="versions/$ver"
  echo "=== $ver -> $dir (port $port) ==="
  mkdir -p "$dir"
  rsync -a --delete \
    --exclude node_modules --exclude .next --exclude versions --exclude tally \
    --exclude test-results --exclude diag --exclude playwright-report \
    "$ROOT/app" "$ROOT/tests" "$ROOT/run-probe.sh" "$ROOT/jsconfig.json" \
    "$ROOT/next.config.mjs" "$dir/"
  node -e "
    const fs=require('fs');
    const p=JSON.parse(fs.readFileSync('$ROOT/package.json','utf8'));
    p.name='next-loading-stall-repro-$ver';
    p.dependencies.next='$ver';
    fs.writeFileSync('$dir/package.json', JSON.stringify(p,null,2));
  "
  sed "s/PORT || 3210/PORT || $port/" "$ROOT/playwright.config.js" > "$dir/playwright.config.js"
  ( cd "$dir" && npm install --no-audit --no-fund >/dev/null 2>&1 \
      && node -e "console.log('  installed', require('next/package.json').version)" \
      && npx next build >/dev/null 2>&1 && echo "  built" ) || echo "  FAILED"
done
echo "done"

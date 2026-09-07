# `loading.js` + Server Action: the transition suspends and is never pinged again

A soft update triggered by a Server Action intermittently never commits. The action's
`POST` returns `200` with the correct payload, no request is left in flight, no error is
thrown — the DOM simply keeps showing the old content forever.

`loading.js` makes it far more likely — but removing it did **not** take the rate to zero
here (1 / 132 still carried the same signature), which is worth knowing because related
reports describe `loading.js` as required.

## The shape that reproduces

Four things have to be true at once. Dropping any one of them took the rate to zero in
our measurements:

1. **`loading.js` on a segment**, creating a `<Suspense>` around that segment's children.
2. **The page is one segment *below* that boundary** (`(app)/loading.jsx` + `(app)/decks/page.jsx`).
   With the page directly in the boundary's own segment we never reproduced it.
3. **The layout at the boundary is `async`** and awaits on every request (auth + a few small
   queries in the real app), so a `RefreshAll` re-suspends the layout too.
4. **The Server Action writes a cookie and calls `revalidatePath`**, which makes Next take the
   `RefreshAll` path (`cookies().set()` alone is enough — `isCookieRevalidated` in
   `server/app-render/action-handler.js`).

Plus: a **production build** (`next build && next start`; `next dev` does not reproduce),
and enough concurrency to lose the race — we run Playwright with `--workers=8` and two
busy-loop processes.

## What React is doing when it hangs

Read straight off the `FiberRoot` after the action settled:

```
pendingLanes=512  suspendedLanes=512  warmLanes=512  entangledLanes=512  pingedLanes=0
```

A transition lane is suspended and **was never pinged**, even though the thenables it parked
on have already fulfilled. The router is done (`actionQueue.pending === null`); the page's
RSC chunk stays at `resolved_model` and is never rendered. `router.refresh()` afterwards
does not recover it — the new lane suspends the same way.

## Measurements

`STALL` = the list never reflected the new sort order within 15s of the click, although
the action's POST returned 200. Two things can produce that, and they are counted apart:
**lost-wakeup** (`suspendedLanes=512, pingedLanes=0` — the bug) and **slow** (lanes back at
0, the update simply landed after the window on an overloaded machine). Only lost-wakeup
counts.

All three versions measured in the same rounds, under the same synthetic load, each run
asserting which Next version answered it (`ROUNDS=20 BATCH=24`, load 2):

| next | lost-wakeup / runs | rate |
|---|---|---|
| **16.2.6** | **220 / 480** | **45.8%** |
| 16.3.4 | 0 / 480 | 0% |
| 16.4.0-canary.19 | 0 / 480 | 0% |
| 16.2.6, `loading.jsx` deleted | 1 / 132 | 0.8% |

🔴 **This reproduces on 16.2.6. It does not demonstrate the bug on 16.3.4.** Earlier batches
here reported `2 / 192` on 16.3.4; that figure was wrong twice over — the denominator was
under-reported (336 runs existed, not 192), and both events came from the one batch that did
not assert its served version. Across everything ever run on 16.3.4: 2 / 816. The interleaved
campaign above, under conditions where the control fires *harder* (45.8% vs the ~22% seen
earlier), produced nothing in 480 runs.

`loading.js` makes it far more likely but is **not required** — removing it left 1 / 132 with
the same signature, which is worth knowing because related reports describe it as necessary.

Two things that make these numbers trustworthy, both added after they caught a real error:

- Every run asks the server which version answered (`/api/version`) and fails on a mismatch.
  With Playwright's `reuseExistingServer` on, a killed server outlived the port check on a
  loaded machine and a whole batch got measured against the previous version under the new label.
- `night-campaign.sh` calibrates on the known-bad version first and refuses to run the campaign
  if it does not reproduce — and now also checks that the calibration and the campaign measured
  the *same application*. They once did not (30 rows/120ms vs 200 rows/200ms), so calibration
  correctly reported "does not reproduce" about a different app and blocked a valid run.

The rate moves a lot with machine load — the same 16.2.6 build measured 45.8%, 22% and 7% in
different sessions — so only compare versions measured in the same round.

## Running it

```sh
npm install
npx next build
ITEM_COUNT=200 BLURB_REPEAT=6 PAGE_DELAY_MS=200 ./run-probe.sh mylabel 144 8 2
```

To compare versions:

```sh
./setup-versions.sh          # one install+build per version, each on its own port
ROUNDS=20 BATCH=24 ./night-campaign.sh
```

`run-probe.sh <label> <runs> <workers> <load-procs>` tallies `STALL` vs `ok` into
`tally/<label>.summary`. It reports how many runs it actually observed: a run that dies for
an unrelated reason must not be counted as a pass.

Because the failure is stochastic, a single green run means nothing. Budget n ≥ 150 for
16.3.4.

Every run asks the server which Next version answered it (`/api/version`) and fails if that
disagrees with the version under test. That check exists because it caught a real error: with
Playwright's `reuseExistingServer` on, a killed server outlived the port check on a loaded
machine and a whole batch was measured against the previous version under the new label.

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

Establishing that it still happens on 16.3.4:

| next | lost-wakeup / runs |
|---|---|
| 16.2.6 | 5 / 72, 16 / 72 (see note) |
| **16.3.4** | **2 / 192** |
| 16.4.0-canary.19 | 0 / 141 |
| 16.2.6, `loading.jsx` deleted | 1 / 132 |

Note: the rate moves a lot with machine load — the same 16.2.6 build measured 22% starting
from a 1-minute load average of ~31 and 7% starting from ~13. Batches taken hours apart are
therefore not comparable to each other, so the numbers above establish *that* 16.3.4 still
reproduces, not by how much the rate differs between versions. A version comparison needs
all versions measured in the same round under the same load: `run-interleaved.sh` does that,
and `night-campaign.sh` calibrates the load on 16.2.6 first and refuses to run the campaign
if the known-bad version does not reproduce (a quiet machine reads 0 everywhere, which looks
exactly like "fixed").

[#95391](https://github.com/vercel/next.js/pull/95391) (in 16.3.0) clearly helped, but
16.3.4 still reproduces.

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

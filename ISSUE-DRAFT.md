# Server Action update never commits: a transition lane stays suspended and is never pinged

### Link to the code that reproduces this issue

<REPRO_URL>

### To Reproduce

```sh
npm install
npx next build
ITEM_COUNT=200 BLURB_REPEAT=6 PAGE_DELAY_MS=200 ./run-probe.sh mine 144 8 2
```

`run-probe.sh` clicks the Server Action button and watches whether the list ever reflects the
new order, over N parallel Playwright runs with two busy-loop processes competing for CPU, then
prints a tally. The failure is stochastic — a single run proves nothing, so please budget
n ≥ 150 on 16.3.4.

### Current vs. Expected behavior

**Expected:** the Server Action writes a cookie, calls `revalidatePath`, and the page
re-renders with the new order.

**Current:** intermittently the page never updates. The action's `POST` returns `200` with a
correct payload, nothing is left in flight, no error is logged, and the old DOM stays
indefinitely (observed out to 60s). A later `router.refresh()` does not recover it — the new
lane suspends the same way.

Read off the `FiberRoot` after the action has settled:

```
pendingLanes=512  suspendedLanes=512  warmLanes=512  entangledLanes=512  pingedLanes=0
```

A transition lane is suspended and was **never pinged**, although the thenables the boundary
parked on have already fulfilled. `actionQueue.pending` is `null` (the router has finished);
the page's RSC chunk sits at `resolved_model` and is never rendered.

### Rates measured

Same machine, same knobs. A run is only counted when the lane signature above is present — a
run that merely missed the 15s window on a loaded machine ends with lanes back at `0` and is
tallied separately, not as this bug.

| config | stalls / runs |
|---|---|
| 16.2.6 | 5 / 72, and 16 / 72 in an earlier batch |
| **16.3.4** | **2 / 192** |
| 16.4.0-canary.19 | 0 / 141 |
| 16.2.6, `app/(app)/loading.jsx` deleted | 1 / 132 |

#95391 (shipped in 16.3.0) clearly took a large bite out of this, but 16.3.4 still reproduces.

Three caveats, so the table is not over-read:

- **`loading.js` raises the rate but is not strictly required.** I expected removing it to take
  this to zero — related reports describe it as necessary — and it did not: 1 / 132 still
  carried the exact lane signature. Note the no-`loading.js` arm ran at a *higher* load (1-min
  load average 61 → 168) than the arm that produced 5 / 72 (13 → 58), so load does not explain
  the reduction; if anything it understates it.
- **The rate moves a lot with machine load.** The same 16.2.6 build measured 22% starting from
  a load average around 31 and 7% starting from around 13, so batches taken hours apart are not
  comparable to each other. The table establishes *that* 16.3.4 still reproduces, not by how
  much the rate differs between versions. (A properly interleaved comparison is running; I will
  add it as a comment.)
- **0 / 141 on canary is not evidence that canary fixed it.** At a ~1% rate, 141 runs cannot
  distinguish "fixed" from "not seen yet".

### What the shape needs

Four things are present in the reproduction:

1. `loading.js` on a segment (the `<Suspense>` it creates) — see the caveat above.
2. The page sits one segment **below** that boundary (`(app)/loading.jsx` + `(app)/decks/page.jsx`).
3. The layout at that boundary is `async` and awaits on every request, so a `RefreshAll`
   re-suspends the layout too.
4. The Server Action writes a cookie **and** calls `revalidatePath` (either alone is enough to
   put Next on the `RefreshAll` path, via `isCookieRevalidated` in
   `server/app-render/action-handler.js`).

Also required: a **production build**. `next dev` never reproduced it here.

I first tried the obvious minimal shape — page directly in the boundary's own segment, plain
synchronous layout — and got **0 / 24 on 16.2.6** across four variations (plain click; a
concurrent navigation; an 800ms server delay; a 200-row payload of client components). Adding
(2) and (3) produced 5 / 24 immediately, with the lane signature above. **I changed those two
together, so I have not isolated which of them matters** — only that the naive shape did not
reproduce and this one does. `run-ablations.sh` in the repo separates them.

### Additional context

This came out of a real app where the same lane signature shows up at 23.1% on 16.2.6 and 2.6%
on 16.3.4 (n = 117 each), so the reduction is not an artifact of the reduction itself.

Every probe run asks the server which Next version answered it (`/api/version`) and fails if
that disagrees with the version under test. That check is in the repo because it caught a real
error in my own measurements: with Playwright's `reuseExistingServer` enabled, a killed server
outlived the port check on a loaded machine, and a whole batch got measured against the previous
version under the new label.

Related: #86151 / #95391 (fixed the bulk of this), #84299, #86055, #97036, #96233.

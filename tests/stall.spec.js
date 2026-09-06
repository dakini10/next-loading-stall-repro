const { test, expect } = require("@playwright/test");

/**
 * Click the Server Action button and watch whether the DOM ever reflects the new
 * order. `STALL` = the list never changed inside the window, even though the
 * action's POST resolved.
 *
 * The lane snapshot is read straight off the FiberRoot so the report can say what
 * React was doing, not just that the pixels did not move.
 */

const N = Number(process.env.RUNS || 6);
const WINDOW_MS = Number(process.env.WINDOW_MS || 15000);

const SNAPSHOT = `(() => {
  const items = Array.from(document.querySelectorAll('[data-testid="item"]')).map((n) => (n.textContent || "").trim());
  const sort = document.querySelector('[data-testid="current-sort"]')?.textContent ?? null;
  const key = Object.keys(document).find((k) => k.startsWith("__reactContainer$"));
  const hostRoot = key ? document[key] : null;
  if (!hostRoot) return { error: "no react container", items, sort };
  const fiberRoot = hostRoot.stateNode;
  const lanes = {
    pendingLanes: fiberRoot.pendingLanes,
    suspendedLanes: fiberRoot.suspendedLanes,
    pingedLanes: fiberRoot.pingedLanes,
    expiredLanes: fiberRoot.expiredLanes,
    warmLanes: fiberRoot.warmLanes,
    entangledLanes: fiberRoot.entangledLanes,
    callbackPriority: fiberRoot.callbackPriority,
  };
  // Any Suspense fiber currently showing a fallback, plus the state of the
  // thenables it is parked on.
  const suspended = [];
  const stack = [fiberRoot.current];
  let guard = 0;
  while (stack.length && guard++ < 200000) {
    const f = stack.pop();
    if (!f) continue;
    if (f.tag === 13 && f.memoizedState !== null) {
      const q = f.updateQueue;
      const retry = q && q.retryQueue ? Array.from(q.retryQueue).map((w) => (w && w.status) || "untracked") : null;
      suspended.push({ lanes: f.lanes, childLanes: f.childLanes, retryQueue: retry });
    }
    if (f.child) stack.push(f.child);
    if (f.sibling) stack.push(f.sibling);
  }
  return { items, sort, lanes, suspended, skeleton: !!document.querySelector('[data-testid="skeleton"]') };
})()`;

for (let i = 1; i <= N; i++) {
  test(`run ${i}`, async ({ page }, testInfo) => {
    await page.context().clearCookies();
    await page.addInitScript(() => {
      window.__actionPost = null;
      const of = window.fetch;
      window.fetch = async (...a) => {
        const started = Date.now();
        const res = await of(...a);
        try {
          const isAction = res.headers.get("x-action-redirect") !== null || (a[1] && a[1].method === "POST");
          if (isAction) window.__actionPost = { started, resolved: Date.now(), status: res.status };
        } catch {}
        return res;
      };
    });

    // Prove which build answered, before measuring anything with it.
    const served = await (await page.request.get("/api/version")).json();
    if (process.env.EXPECT_NEXT && served.next !== process.env.EXPECT_NEXT) {
      throw new Error(
        `served next=${served.next} but EXPECT_NEXT=${process.env.EXPECT_NEXT} -- wrong build answered`,
      );
    }
    await page.goto(process.env.PROBE_PATH || "/decks");
    await expect(page.getByTestId("item").first()).toBeVisible();
    const before = await page.evaluate(SNAPSHOT);
    const beforeOrder = JSON.stringify(before.items);
    expect(before.items.length).toBe(Number(process.env.ITEM_COUNT || 30));

    const clickedAt = Date.now();
    // MODE picks which of the upstream-named shapes we drive:
    //   plain  = click the action and wait (the shape the real app stalls in)
    //   double = call the action twice in a row (#84299 "double calling server action")
    //   nav    = start a navigation while the action is in flight (#95391 title)
    const MODE = process.env.MODE || "plain";
    await page.getByTestId("sort-desc").click();
    if (MODE === "double") {
      await page.getByTestId("sort-desc").click();
    } else if (MODE === "nav") {
      await page.waitForTimeout(Number(process.env.NAV_DELAY_MS || 5));
      await page.getByTestId("nav-3").click();
      await page.goBack();
    }

    let changedAt = null;
    while (Date.now() - clickedAt < WINDOW_MS) {
      const cur = JSON.stringify(
        await page.evaluate(() =>
          Array.from(document.querySelectorAll('[data-testid="item"]')).map((n) => (n.textContent || "").trim()),
        ),
      );
      if (cur !== beforeOrder) {
        changedAt = Date.now();
        break;
      }
      await page.waitForTimeout(50);
    }

    const last = await page.evaluate(SNAPSHOT);
    const actionPost = await page.evaluate(() => window.__actionPost);
    const verdict = changedAt === null ? "STALL" : "ok";
    // eslint-disable-next-line no-console
    console.log(
      `[PROBE] ${i}/${N} next=${served.next} mode=${MODE} ${verdict} clickToDom=${changedAt === null ? "null" : changedAt - clickedAt}ms ` +
        `action=${JSON.stringify(actionPost)} lanes=${JSON.stringify(last.lanes)} ` +
        `suspended=${JSON.stringify(last.suspended)} skeleton=${last.skeleton} sort=${JSON.stringify(last.sort)}`,
    );
    await testInfo.attach("probe.json", {
      body: JSON.stringify({ i, verdict, clickedAt, changedAt, actionPost, before, last }, null, 2),
      contentType: "application/json",
    });
    // The probe records; it does not assert. Counting happens in the runner.
  });
}

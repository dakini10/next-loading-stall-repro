// This file is the whole point of the repro: it makes Next wrap the segment's
// children in a <Suspense>. Delete it and the stall goes away.
export default function Loading() {
  return <div data-testid="skeleton">loading…</div>;
}

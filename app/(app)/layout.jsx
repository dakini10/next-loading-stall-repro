import Link from "next/link";
import { cookies } from "next/headers";

import Providers from "./Providers";

// The real app's authed layout is async: it awaits an auth round-trip plus a
// handful of small queries (draft count, feature gates, billing context) on every
// request, so a RefreshAll re-runs and re-suspends the layout too.
const LAYOUT_AWAITS = Number(process.env.LAYOUT_AWAITS ?? 6);
const LAYOUT_DELAY = Number(process.env.LAYOUT_DELAY_MS ?? 15);
const LINKS = Array.from({ length: 11 }, (_, i) => i + 1);

export default async function AppLayout({ children }) {
  await cookies();
  for (let i = 0; i < LAYOUT_AWAITS; i++) {
    await new Promise((r) => setTimeout(r, LAYOUT_DELAY));
  }

  return (
    <Providers>
      <div style={{ display: "flex", gap: 24, padding: 16 }}>
        <nav style={{ display: "flex", flexDirection: "column", gap: 4, minWidth: 140 }}>
          <Link href="/decks" data-testid="nav-decks">
            decks
          </Link>
          {LINKS.map((n) => (
            <Link key={n} href={`/p/${n}`} data-testid={`nav-${n}`}>
              page {n}
            </Link>
          ))}
        </nav>
        <main style={{ flex: 1 }}>{children}</main>
      </div>
    </Providers>
  );
}

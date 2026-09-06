import { cookies } from "next/headers";

import Item from "../Item";
import { setSortAction } from "../actions";

const COUNT = Number(process.env.ITEM_COUNT ?? 30);
const DELAY = Number(process.env.PAGE_DELAY_MS ?? 120);
const BLURB = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor ".repeat(
  Number(process.env.BLURB_REPEAT ?? 1),
);

const ITEMS = Array.from({ length: COUNT }, (_, i) => `item-${String(i + 1).padStart(3, "0")}`);

export default async function Page() {
  const store = await cookies();
  const sort = store.get("sort")?.value === "desc" ? "desc" : "asc";

  // Stand in for the app's database round-trip.
  await new Promise((r) => setTimeout(r, DELAY));

  const items = sort === "desc" ? [...ITEMS].reverse() : ITEMS;

  return (
    <div>
      <form action={setSortAction} style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <button name="sort" value="asc" data-testid="sort-asc" aria-pressed={sort === "asc"}>
          asc
        </button>
        <button name="sort" value="desc" data-testid="sort-desc" aria-pressed={sort === "desc"}>
          desc
        </button>
      </form>
      <p data-testid="current-sort">sort={sort}</p>
      <ul>
        {items.map((it) => (
          <Item key={it} label={it} blurb={BLURB} />
        ))}
      </ul>
    </div>
  );
}

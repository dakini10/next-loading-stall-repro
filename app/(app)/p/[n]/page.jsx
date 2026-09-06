import { cookies } from "next/headers";

export default async function P({ params }) {
  const { n } = await params;
  await cookies(); // keep the route dynamic, like every route in the real app
  await new Promise((r) => setTimeout(r, 60));
  return <div data-testid="p-page">page {n}</div>;
}

export const dynamic = "force-dynamic";

const START = Date.now();

// The probe asserts against this. A measurement must be able to prove which build
// answered it -- the label on the run is not evidence.
export async function GET() {
  const mod = await import("next/package.json");
  const version = mod.version ?? mod.default?.version ?? "unknown";
  return Response.json({ next: version, pid: process.pid, startedAt: START });
}

import "server-only";

import { NextResponse } from "next/server";

import { isSupabaseReady } from "@/lib/health-readiness";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  if (await isSupabaseReady()) {
    return NextResponse.json(
      { status: "ready" },
      { headers: { "Cache-Control": "no-store" } },
    );
  }

  return NextResponse.json(
    { status: "unavailable" },
    { status: 503, headers: { "Cache-Control": "no-store" } },
  );
}

import { NextResponse } from "next/server";
import { NO_STORE_HEADERS } from "@/lib/config";

// Never pre-render or cache: the ALB must see a live answer from this process.
export const dynamic = "force-dynamic";

/**
 * ALB target-group health check endpoint.
 *
 * Deliberately trivial: it does not call EC2 metadata or anything external, so
 * a slow dependency can never make a working instance look unhealthy. If the
 * Node.js process is up and serving HTTP, this returns 200.
 */
export function GET() {
  return NextResponse.json(
    { status: "ok", uptimeSeconds: Math.round(process.uptime()) },
    { status: 200, headers: NO_STORE_HEADERS },
  );
}

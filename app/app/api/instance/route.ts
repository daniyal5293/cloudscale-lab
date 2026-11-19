import os from "node:os";
import { NextResponse } from "next/server";
import { NO_STORE_HEADERS, getScalingConfig } from "@/lib/config";
import { getInstanceIdentity } from "@/lib/metadata";

// Every response must come from the instance that actually handled the request.
export const dynamic = "force-dynamic";

/**
 * Returns which EC2 instance served this request. Calling it repeatedly through
 * the ALB shows requests being spread across instances.
 */
export async function GET() {
  const identity = await getInstanceIdentity();

  return NextResponse.json(
    {
      instanceId: identity.instanceId,
      availabilityZone: identity.availabilityZone,
      hostname: identity.hostname,
      containerId: os.hostname(),
      source: identity.source,
      appVersion: getScalingConfig().appVersion,
      timestamp: new Date().toISOString(),
    },
    { headers: NO_STORE_HEADERS },
  );
}

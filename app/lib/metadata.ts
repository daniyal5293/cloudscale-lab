import os from "node:os";

/**
 * Identity of the EC2 instance serving the current request.
 *
 * On EC2 the values come from the Instance Metadata Service (IMDS) using
 * IMDSv2 (session-token based). Off EC2 (local development, CI, Docker Desktop)
 * IMDS is unreachable, so a clearly-labelled fallback is returned instead.
 */
export interface InstanceIdentity {
  instanceId: string;
  availabilityZone: string;
  hostname: string;
  source: "ec2-imds-v2" | "local-fallback";
}

const IMDS_BASE = process.env.IMDS_ENDPOINT ?? "http://169.254.169.254";
// Keep this short: if IMDS is unreachable we must not slow the request down.
const REQUEST_TIMEOUT_MS = 1000;
const TOKEN_TTL_SECONDS = 300;
// After a failed lookup, serve the fallback for a while before trying again.
const RETRY_AFTER_FAILURE_MS = 30_000;

// An instance's ID, AZ and private hostname never change during its lifetime,
// so a successful lookup is cached for the life of the process. This keeps
// /api/instance cheap under load-testing traffic (no IMDS call per request).
let cachedIdentity: InstanceIdentity | null = null;
let lastFailureAt = 0;
let inFlight: Promise<InstanceIdentity> | null = null;

async function imdsRequest(path: string, init: RequestInit = {}): Promise<string> {
  const res = await fetch(`${IMDS_BASE}${path}`, {
    ...init,
    cache: "no-store",
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!res.ok) {
    throw new Error(`IMDS ${path} returned HTTP ${res.status}`);
  }
  return (await res.text()).trim();
}

async function fetchFromImds(): Promise<InstanceIdentity> {
  // Step 1 (IMDSv2): obtain a short-lived session token with a PUT request.
  // The launch template sets http_tokens = "required", so token-less (IMDSv1)
  // requests are rejected. Hop limit 2 lets the token response reach a container.
  const token = await imdsRequest("/latest/api/token", {
    method: "PUT",
    headers: { "X-aws-ec2-metadata-token-ttl-seconds": String(TOKEN_TTL_SECONDS) },
  });

  // Step 2: read the metadata we need, presenting the token on every request.
  const headers = { "X-aws-ec2-metadata-token": token };
  const [instanceId, availabilityZone, hostname] = await Promise.all([
    imdsRequest("/latest/meta-data/instance-id", { headers }),
    imdsRequest("/latest/meta-data/placement/availability-zone", { headers }),
    imdsRequest("/latest/meta-data/local-hostname", { headers }),
  ]);

  return { instanceId, availabilityZone, hostname, source: "ec2-imds-v2" };
}

function localFallback(): InstanceIdentity {
  return {
    instanceId: "local-dev",
    availabilityZone: "local",
    hostname: os.hostname(),
    source: "local-fallback",
  };
}

export async function getInstanceIdentity(): Promise<InstanceIdentity> {
  if (cachedIdentity) return cachedIdentity;
  if (process.env.DISABLE_IMDS === "true") return localFallback();
  if (Date.now() - lastFailureAt < RETRY_AFTER_FAILURE_MS) return localFallback();

  // De-duplicate concurrent lookups (e.g. a burst of requests right after boot).
  inFlight ??= fetchFromImds()
    .then((identity) => {
      cachedIdentity = identity;
      console.log(`[metadata] running on ${identity.instanceId} (${identity.availabilityZone})`);
      return identity;
    })
    .catch((error: unknown) => {
      lastFailureAt = Date.now();
      const reason = error instanceof Error ? error.message : String(error);
      console.warn(`[metadata] EC2 metadata unavailable, using local fallback: ${reason}`);
      return localFallback();
    })
    .finally(() => {
      inFlight = null;
    });

  return inFlight;
}

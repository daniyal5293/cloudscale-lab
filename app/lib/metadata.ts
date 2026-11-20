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
// Short enough not to stall a request when IMDS is unreachable, long enough to
// survive the first request after a cold start (when Next.js is still loading
// page code and the event loop is busy, a 1 s timer could fire spuriously).
const REQUEST_TIMEOUT_MS = 2000;
const TOKEN_TTL_SECONDS = 300;
// After a failed lookup, serve the fallback briefly before trying again.
const RETRY_AFTER_FAILURE_MS = 10_000;

// An instance's ID, AZ and private hostname never change during its lifetime,
// so a successful lookup is cached for the life of the process. This keeps
// /api/instance cheap under load-testing traffic (no IMDS call per request).
//
// The cache lives on globalThis because Next.js bundles pages, route handlers
// and instrumentation separately: plain module-level variables would give each
// bundle its own copy, so the homepage could still be on the fallback while
// /api/instance already knew the real instance ID.
interface MetadataCache {
  identity: InstanceIdentity | null;
  lastFailureAt: number;
  inFlight: Promise<InstanceIdentity> | null;
}

const globalForMetadata = globalThis as typeof globalThis & {
  __cloudscaleMetadata?: MetadataCache;
};
const cache: MetadataCache = (globalForMetadata.__cloudscaleMetadata ??= {
  identity: null,
  lastFailureAt: 0,
  inFlight: null,
});

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
  if (cache.identity) return cache.identity;
  if (process.env.DISABLE_IMDS === "true") return localFallback();
  if (Date.now() - cache.lastFailureAt < RETRY_AFTER_FAILURE_MS) return localFallback();

  // De-duplicate concurrent lookups (e.g. a burst of requests right after boot).
  cache.inFlight ??= fetchFromImds()
    .then((identity) => {
      cache.identity = identity;
      console.log(`[metadata] running on ${identity.instanceId} (${identity.availabilityZone})`);
      return identity;
    })
    .catch((error: unknown) => {
      cache.lastFailureAt = Date.now();
      const reason = error instanceof Error ? error.message : String(error);
      console.warn(`[metadata] EC2 metadata unavailable, using local fallback: ${reason}`);
      return localFallback();
    })
    .finally(() => {
      cache.inFlight = null;
    });

  return cache.inFlight;
}

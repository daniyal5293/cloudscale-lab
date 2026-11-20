/**
 * Next.js calls register() once when the server process starts.
 *
 * Warm the EC2 metadata cache at startup so the very first page view already
 * shows the real instance ID. Fire-and-forget: startup is never delayed, and
 * off EC2 the lookup simply falls back to "local-dev".
 */
export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const { getInstanceIdentity } = await import("./lib/metadata");
    void getInstanceIdentity();
  }
}

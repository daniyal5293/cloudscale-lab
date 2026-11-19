import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // "standalone" emits a minimal Node.js server (.next/standalone/server.js) that
  // contains only the files needed at runtime, which keeps the Docker image small.
  output: "standalone",
  // Do not advertise the framework in response headers.
  poweredByHeader: false,
  // No image optimisation is needed for this demo; avoids pulling in `sharp`.
  images: { unoptimized: true },
};

export default nextConfig;

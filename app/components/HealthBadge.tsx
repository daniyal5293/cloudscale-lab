"use client";

import { useEffect, useState } from "react";

type Status = "checking" | "healthy" | "unhealthy";

const POLL_INTERVAL_MS = 5000;

/**
 * Polls /api/health (the same endpoint the ALB health check uses) and shows
 * the result. Through the ALB, each poll may be answered by a different target.
 */
export function HealthBadge() {
  const [status, setStatus] = useState<Status>("checking");
  const [latencyMs, setLatencyMs] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function check() {
      const started = performance.now();
      try {
        const res = await fetch("/api/health", { cache: "no-store" });
        if (cancelled) return;
        setStatus(res.ok ? "healthy" : "unhealthy");
      } catch {
        if (cancelled) return;
        setStatus("unhealthy");
      }
      setLatencyMs(Math.round(performance.now() - started));
    }

    check();
    const timer = setInterval(check, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, []);

  const label = status === "checking" ? "Checking…" : status === "healthy" ? "Healthy" : "Unhealthy";

  return (
    <span className={`badge badge-${status}`} title="Result of GET /api/health, refreshed every 5 s">
      <span className="dot" aria-hidden="true" />
      {label}
      {latencyMs !== null && <span className="latency">{latencyMs} ms</span>}
    </span>
  );
}

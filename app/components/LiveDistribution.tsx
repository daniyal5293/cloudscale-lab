"use client";

import { useState } from "react";

interface InstanceResponse {
  instanceId: string;
  availabilityZone: string;
}

interface Tally {
  instanceId: string;
  availabilityZone: string;
  hits: number;
}

const BATCH_SIZES = [10, 25, 50] as const;
const CONCURRENCY = 4;

/**
 * Sends a batch of requests to /api/instance and counts which instance answered
 * each one. With 2+ healthy targets, the ALB spreads requests across them.
 */
export function LiveDistribution() {
  const [batchSize, setBatchSize] = useState<number>(25);
  const [running, setRunning] = useState(false);
  const [tallies, setTallies] = useState<Tally[]>([]);
  const [errors, setErrors] = useState(0);
  const [sent, setSent] = useState(0);

  async function run() {
    setRunning(true);
    setTallies([]);
    setErrors(0);
    setSent(0);

    const counts = new Map<string, Tally>();
    let next = 0;

    async function worker() {
      while (next < batchSize) {
        next += 1;
        try {
          const res = await fetch("/api/instance", { cache: "no-store" });
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          const body = (await res.json()) as InstanceResponse;
          const entry = counts.get(body.instanceId) ?? {
            instanceId: body.instanceId,
            availabilityZone: body.availabilityZone,
            hits: 0,
          };
          entry.hits += 1;
          counts.set(body.instanceId, entry);
          setTallies([...counts.values()].sort((a, b) => b.hits - a.hits));
        } catch {
          setErrors((e) => e + 1);
        }
        setSent((s) => s + 1);
      }
    }

    await Promise.all(Array.from({ length: CONCURRENCY }, worker));
    setRunning(false);
  }

  const maxHits = Math.max(1, ...tallies.map((t) => t.hits));

  return (
    <section className="card">
      <h2>Live load-distribution tester</h2>
      <p className="muted">
        Sends requests from your browser to <code>/api/instance</code> and counts which EC2 instance
        answered each one. When the Auto Scaling Group has scaled out, you should see several
        instance IDs.
      </p>

      <div className="controls">
        <label>
          Requests:{" "}
          <select
            value={batchSize}
            onChange={(e) => setBatchSize(Number(e.target.value))}
            disabled={running}
          >
            {BATCH_SIZES.map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </label>
        <button type="button" onClick={run} disabled={running}>
          {running ? `Sending… ${sent}/${batchSize}` : "Send requests"}
        </button>
        {sent > 0 && !running && (
          <span className="muted">
            {sent} sent · {tallies.length} instance{tallies.length === 1 ? "" : "s"} · {errors} error
            {errors === 1 ? "" : "s"}
          </span>
        )}
      </div>

      {tallies.length > 0 && (
        <ul className="bars">
          {tallies.map((t) => (
            <li key={t.instanceId}>
              <span className="mono bar-label">
                {t.instanceId} <span className="muted">({t.availabilityZone})</span>
              </span>
              <span className="bar-track">
                <span className="bar-fill" style={{ width: `${(t.hits / maxHits) * 100}%` }} />
              </span>
              <span className="mono bar-count">{t.hits}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

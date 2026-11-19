// CloudScale Lab: k6 load test for the ALB + Auto Scaling demo.
//
// Usage (from the repository root):
//   k6 run -e BASE_URL=http://<alb-dns-name> -e SCENARIO=normal       load-testing/k6-load-test.js
//   k6 run -e BASE_URL=http://<alb-dns-name> -e SCENARIO=spike        load-testing/k6-load-test.js
//   k6 run -e BASE_URL=http://<alb-dns-name> -e SCENARIO=scalein      load-testing/k6-load-test.js
//   k6 run -e BASE_URL=http://<alb-dns-name> -e SCENARIO=distribution load-testing/k6-load-test.js
//   k6 run -e BASE_URL=http://localhost:3000 -e SCENARIO=smoke        load-testing/k6-load-test.js
//
// Each virtual user (VU) sends one request, then sleeps ~1 s, so
// requests/second ≈ number of VUs. Scaling target default: 600 req/target/min = 10 req/s.

import http from "k6/http";
import { check, sleep } from "k6";
import exec from "k6/execution";
import { Counter, Rate } from "k6/metrics";

const BASE_URL = (__ENV.BASE_URL || "").replace(/\/+$/, "");
if (!BASE_URL) {
  throw new Error("BASE_URL is required, e.g. -e BASE_URL=http://my-alb-123.us-east-1.elb.amazonaws.com");
}
const SCENARIO = __ENV.SCENARIO || "normal";
const ENDPOINT = __ENV.ENDPOINT || "/api/instance";
const RESULTS_DIR = __ENV.RESULTS_DIR || "load-testing/results";

// ---------------------------------------------------------------------------
// Scenario profiles. Sized to trigger scaling while keeping traffic (and the
// ALB LCU / data-transfer cost) tiny: the spike sends roughly 25,000 requests.
// ---------------------------------------------------------------------------
const PROFILES = {
  // Sanity check against a local container. Not for AWS demos.
  smoke: {
    executor: "per-vu-iterations",
    vus: 1,
    iterations: 10,
    maxDuration: "1m",
    pause: 0.2,
  },

  // Scenario A: normal load. ~3 req/s ≈ 180 req/min, far below the 600 target.
  // Expected: the single instance handles everything; no scaling.
  normal: {
    executor: "ramping-vus",
    startVUs: 0,
    stages: [
      { duration: "1m", target: 3 },
      { duration: "4m", target: 3 },
      { duration: "30s", target: 0 },
    ],
    gracefulRampDown: "10s",
    pause: 1,
  },

  // Scenario B: traffic spike. ~30 req/s ≈ 1,800 req/min against 1 instance.
  // Expected: after ~3 one-minute datapoints above target, desired capacity
  // becomes ceil(1 × 1800 / 600) = 3 (the max). New targets turn healthy
  // ~3–5 min later and requests per target drop to ~600.
  spike: {
    executor: "ramping-vus",
    startVUs: 0,
    stages: [
      { duration: "1m", target: 5 }, // warm up
      { duration: "2m", target: 30 }, // ramp up
      { duration: "10m", target: 30 }, // sustained peak: scale-out happens here
      { duration: "2m", target: 0 }, // ramp down
    ],
    gracefulRampDown: "10s",
    pause: 1,
  },

  // Scenario C: load reduction. A gentle trickle (~0.5 req/s ≈ 30 req/min).
  // Traffic must NOT stop completely: with zero requests the
  // RequestCountPerTarget metric has no datapoints, the scale-in alarm sits
  // in INSUFFICIENT_DATA, and the group never scales in.
  // Expected: after ~15 consecutive low datapoints, the group steps back to 1.
  scalein: {
    executor: "constant-vus",
    vus: 1,
    duration: "25m",
    pause: 2,
  },

  // Scenario D: load distribution. Run while 2–3 targets are healthy.
  // Expected: responses come from several different instance IDs.
  distribution: {
    executor: "per-vu-iterations",
    vus: 2,
    iterations: 60,
    maxDuration: "5m",
    pause: 0.2,
  },
};

const profile = PROFILES[SCENARIO];
if (!profile) {
  throw new Error(`Unknown SCENARIO "${SCENARIO}". Use one of: ${Object.keys(PROFILES).join(", ")}`);
}
const { pause, ...executorConfig } = profile;

export const options = {
  scenarios: {
    [SCENARIO]: { ...executorConfig, exec: "hit" },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"], // < 1% errors
    http_req_duration: ["p(95)<1000"], // 95% of requests under 1 s
    checks: ["rate>0.99"],
  },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "max"],
  // Identify the traffic in ALB access logs / server logs.
  userAgent: "cloudscale-lab-k6/1.0",
};

const servedByInstance = new Rate("served_by_ec2_instance");
const instanceResponses = new Counter("instance_responses");

// Per-VU tally of which instance answered (used in the distribution scenario).
const seen = {};

export function hit() {
  const res = http.get(`${BASE_URL}${ENDPOINT}`, {
    tags: { endpoint: ENDPOINT },
    headers: { "Cache-Control": "no-cache" },
  });

  let instanceId = "unknown";
  try {
    instanceId = res.json("instanceId") || "unknown";
  } catch {
    // Non-JSON body (e.g. an ALB 502/503 HTML page). The status check fails below.
  }

  check(res, {
    "status is 200": (r) => r.status === 200,
    "body has instanceId": () => instanceId !== "unknown",
  });

  servedByInstance.add(instanceId.startsWith("i-"));
  instanceResponses.add(1, { instance: instanceId });

  if (SCENARIO === "distribution") {
    seen[instanceId] = (seen[instanceId] || 0) + 1;
    const lastIteration = exec.vu.iterationInScenario === profile.iterations - 1;
    if (lastIteration) {
      console.log(`VU ${exec.vu.idInTest} responses by instance: ${JSON.stringify(seen)}`);
    }
  }

  sleep(pause);
}

// ---------------------------------------------------------------------------
// End-of-test report: printed to the terminal and saved as JSON.
// ---------------------------------------------------------------------------
function fmtMs(value) {
  return value === undefined ? "n/a" : `${value.toFixed(1)} ms`;
}

export function handleSummary(data) {
  const m = data.metrics;
  const duration = m.http_req_duration ? m.http_req_duration.values : {};
  const reqs = m.http_reqs ? m.http_reqs.values : { count: 0, rate: 0 };
  const failed = m.http_req_failed ? m.http_req_failed.values.rate : 0;
  const checksRate = m.checks ? m.checks.values.rate : 0;

  const thresholdLines = [];
  for (const [name, metric] of Object.entries(m)) {
    if (!metric.thresholds) continue;
    for (const [expr, result] of Object.entries(metric.thresholds)) {
      thresholdLines.push(`  ${result.ok ? "PASS" : "FAIL"}  ${name}: ${expr}`);
    }
  }

  const report = {
    scenario: SCENARIO,
    baseUrl: BASE_URL,
    endpoint: ENDPOINT,
    finishedAt: new Date().toISOString(),
    totalRequests: reqs.count,
    requestsPerSecond: Number(reqs.rate.toFixed(2)),
    errorRate: Number(failed.toFixed(4)),
    checksPassRate: Number(checksRate.toFixed(4)),
    latencyMs: {
      avg: duration.avg,
      median: duration.med,
      p90: duration["p(90)"],
      p95: duration["p(95)"],
      max: duration.max,
    },
  };

  const text = [
    "",
    "================ CloudScale Lab: k6 summary ================",
    `Scenario          : ${SCENARIO}`,
    `Target            : ${BASE_URL}${ENDPOINT}`,
    `Total requests    : ${reqs.count}`,
    `Request rate      : ${reqs.rate.toFixed(2)} req/s (≈ ${(reqs.rate * 60).toFixed(0)} req/min)`,
    `Error rate        : ${(failed * 100).toFixed(2)} %`,
    `Checks passed     : ${(checksRate * 100).toFixed(2)} %`,
    `Latency avg       : ${fmtMs(duration.avg)}`,
    `Latency median    : ${fmtMs(duration.med)}`,
    `Latency p95       : ${fmtMs(duration["p(95)"])}`,
    `Latency max       : ${fmtMs(duration.max)}`,
    "Thresholds:",
    ...thresholdLines,
    "=============================================================",
    "",
  ].join("\n");

  const stamp = report.finishedAt.replace(/[:.]/g, "-");
  return {
    stdout: text,
    [`${RESULTS_DIR}/${SCENARIO}-${stamp}.json`]: JSON.stringify(report, null, 2),
  };
}

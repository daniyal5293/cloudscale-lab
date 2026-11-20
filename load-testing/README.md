# Load testing with k6

[k6](https://k6.io) is an open-source load-testing tool: you describe virtual users (VUs) in JavaScript, and k6
runs them and reports latency and error statistics. It runs **on your own computer**, so there's no extra EC2
cost for a load generator.

## Install

```powershell
winget install --id GrafanaLabs.k6 -e
k6 version
```

## Run (from the repository root)

```powershell
$alb = terraform -chdir=infrastructure/terraform output -raw alb_url

k6 run -e BASE_URL=$alb -e SCENARIO=normal       load-testing/k6-load-test.js   # A
k6 run -e BASE_URL=$alb -e SCENARIO=spike        load-testing/k6-load-test.js   # B
k6 run -e BASE_URL=$alb -e SCENARIO=scalein      load-testing/k6-load-test.js   # C
k6 run -e BASE_URL=$alb -e SCENARIO=distribution load-testing/k6-load-test.js   # D

# Local sanity check against docker compose (not for AWS):
k6 run -e BASE_URL=http://localhost:3000 -e SCENARIO=smoke load-testing/k6-load-test.js
```

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `BASE_URL` | yes | n/a | ALB URL, e.g. `http://cloudscale-lab-demo-alb-123.us-east-1.elb.amazonaws.com` |
| `SCENARIO` | no | `normal` | `smoke`, `normal`, `spike`, `scalein`, `distribution` |
| `ENDPOINT` | no | `/api/instance` | Path to request |
| `RESULTS_DIR` | no | `load-testing/results` | Where the JSON summary is written |

## Scenarios

Each VU sends a request and then sleeps about 1 s, so **requests per second ≈ number of VUs**. The scaling target
is **600 requests per target per minute** (10 req/s per instance).

| Scenario | Shape | Traffic | Duration | Expected result |
|---|---|---|---|---|
| **A: normal** | ramp 0→3 VUs, hold, ramp down | ~3 req/s (~180/min) | ~5.5 min | Stays at **1 instance**. Requests per target ≈ 180, well under 600 |
| **B: spike** | 0→5→30 VUs, hold 10 min, ramp down | ~25–30 req/s (~1,500–1,800/min) | 15 min | After ~3 min above target, **desired = 3**. New targets healthy ~3–5 min later |
| **C: scalein** | 1 VU, 2 s pause | ~0.5 req/s (~30/min) | 25 min | After ~15 min below target, capacity steps back to **1** |
| **D: distribution** | 2 VUs × 60 requests | short burst | ~30 s | Logs show responses from **several instance IDs** |
| **demo** (classroom) | 0→30 VUs in 2 min, hold 25 min | ~25 req/s | 28 min | Start ~10 min **before** presenting; scaled to 3 by the time you're on stage |

**Why does scale-in need a trickle of traffic?** With *zero* requests, the ALB publishes no
`RequestCountPerTarget` datapoints. The scale-in alarm then sits in `INSUFFICIENT_DATA` instead of `ALARM`, and the
group never shrinks. A tiny, steady load keeps the metric alive and clearly below target.

**Latency from your PC includes the internet round trip** to us-east-1 (it can be 200–300 ms from South Asia).
The CloudWatch `TargetResponseTime` metric shows the server-side time, which should be a few milliseconds.
Because of that round trip each VU makes slightly fewer than 1 req/s. If the spike only scales to 2 instances,
raise the peak VUs in the `spike` profile, or lower `requests_per_target_per_minute`.

## Reading the output

At the end, k6 prints a summary like this and saves the same data as JSON in `load-testing/results/`:

```
================ CloudScale Lab: k6 summary ================
Scenario          : spike
Total requests    : 23874
Request rate      : 26.52 req/s (≈ 1591 req/min)
Error rate        : 0.00 %
Latency avg       : 248.1 ms
Latency p95       : 301.7 ms
Thresholds:
  PASS  http_req_failed: rate<0.01
  PASS  http_req_duration: p(95)<1000
  PASS  checks: rate>0.99
```
(These numbers are illustrative only; your own run produces the real ones.)

| Metric | Meaning |
|---|---|
| **Request rate** | Throughput the test achieved |
| **Error rate** | Share of requests that failed (non-2xx/3xx or network error). Must stay < 1% |
| **Latency avg / p95** | Mean response time and the time 95% of requests beat. p95 shows what slow users experience |
| **Thresholds** | Pass/fail criteria. k6 exits non-zero if any fails |

## Cost guard

The spike scenario sends about 25,000 tiny requests (~10 MB), which is negligible for ALB LCUs and data transfer.
Don't increase VUs into the thousands: it won't make the demo better, and a t3.micro with *standard* CPU
credits will just throttle.

# CloudScale Lab: Load Test Results (verified on AWS)

**Date:** 2026-11-20 · **Region:** us-east-1 · **Load generator:** k6 v2.4.0 on a local PC (Pakistan → us-east-1)
**Configuration:** t3.micro (unlimited CPU credits), ASG min 1 / max 3, target tracking `ALBRequestCountPerTarget = 600`
**Image:** `ghcr.io/daniyal5293/cloudscale-lab:sha-2e1fc0a`

All numbers below come from real k6 output, CloudWatch metrics and Auto Scaling activity history.

## Summary

| # | Acceptance criterion | Result |
|---|---|---|
| 1 | App deployed on EC2 | ✅ `/api/instance` returns real instance IDs via IMDSv2 |
| 2 | ALB distributes traffic | ✅ 3 instance IDs, even split (see Scenario D) |
| 3 | ASG with configurable capacity | ✅ min 1 / max 3 from Terraform variables |
| 4 | Automatic scale-out | ✅ 1 → 3 at 18:46:08 |
| 5 | Automatic scale-in | ✅ 3 → 2 at 19:09:02, 2 → 1 at 19:10:08 |
| 6 | Different instance IDs | ✅ `i-04994bac1585b6575`, `i-0a6925587c86d7c5c`, `i-0fae9a9ffe4bc9a2c` |
| 7 | Healthy/unhealthy monitoring | ✅ targets `initial` → `unhealthy` (booting) → `healthy`; alarms fired during a real outage and recovered |
| 9 | k6 results | ✅ 4 scenarios, 0.00% errors, all thresholds passed |

## k6 scenario results

| Scenario | Window (PKT) | Requests | Rate | Errors | Avg | p95 | Max | Thresholds |
|---|---|---|---|---|---|---|---|---|
| A: normal | 18:32:05–18:37:37 | 692 | 2.09 req/s | 0.00% | 214.8 ms | 246.0 ms | 591.0 ms | all PASS |
| B: spike | 18:37:56–18:52:57 | 18,147 | 20.16 req/s (peak ≈ 24.8) | 0.00% | 213.3 ms | 222.2 ms | 852.6 ms | all PASS |
| D: distribution | ~18:49 | 120 | n/a | 0.00% | n/a | 220.0 ms | n/a | all PASS |
| C: scale-in | 18:53:05–19:18:08 | 371 | 0.25 req/s | 0.00% | 215.2 ms | 252.1 ms | 547.8 ms | all PASS |

Client-side latency (~210 ms) is dominated by the internet round trip from Pakistan to us-east-1. **Server-side
p95 `TargetResponseTime` in CloudWatch stayed at 2–7 ms** throughout the test.

## Scaling timeline

| Time (PKT) | Event | Evidence |
|---|---|---|
| 18:32 | Scenario A: ~147 req/min on 1 instance, far below 600 → no scaling | CloudWatch `RequestCountPerTarget` |
| 18:38 | Scenario B starts ramping to 30 VUs | k6 |
| 18:41 | `RequestCountPerTarget` ≈ **1,480/min** (2.5 × target) | CloudWatch |
| 18:46:02 | **Scale-out:** "Launching a new EC2 instance" ×2 (desired 1 → 3) | ASG activity history |
| 18:46:28 | New instances `InService`, targets `unhealthy` while booting | target health |
| 18:48:08 / 18:48:28 | Both new targets `healthy` (~2 min after launch) | target health |
| 18:48–18:50 | `RequestCountPerTarget` falls to **≈ 500/min** (near target) with 3 healthy hosts | CloudWatch |
| 18:53 | Load drops to a trickle (≈ 9 req/target/min) | CloudWatch |
| 19:09:02 | **Scale-in:** terminate `i-0fae9a9ffe4bc9a2c` (3 → 2), 16 min after load dropped | ASG activity history |
| 19:10:08 | **Scale-in:** terminate `i-04994bac1585b6575` (2 → 1) | ASG activity history |
| 19:10 | Back at minimum capacity: 1 healthy target | CloudWatch / target health |

Expected behaviour vs observed:
- Scale-out needs **3 one-minute datapoints above target**. Load crossed 600 at about 18:40, plus CloudWatch
  publishing delay → decision at 18:46. ✔
- Desired capacity = `ceil(1 × 1,485 / 600)` = **3**. ✔
- Scale-in needs **15 low datapoints**. Low from 18:53 → scale-in at 19:09. ✔

## Scenario D: load distribution

`scripts/check-distribution.ps1` (60 requests at 18:48:18, while the 3rd target was just turning healthy):

| Instance | AZ | Requests |
|---|---|---|
| i-0a6925587c86d7c5c | us-east-1b | 27 (45%) |
| i-04994bac1585b6575 | us-east-1a | 26 (43%) |
| i-0fae9a9ffe4bc9a2c | us-east-1a | 7 (12%), joined mid-run |

k6 `SCENARIO=distribution` (120 requests, all 3 healthy):

| VU | i-04994bac1585b6575 | i-0a6925587c86d7c5c | i-0fae9a9ffe4bc9a2c |
|---|---|---|---|
| VU 1 | 17 | 25 | 18 |
| VU 2 | 22 | 20 | 18 |

## Issues found during deployment (and fixed)

| Issue | Root cause | Fix |
|---|---|---|
| New instances failed health checks and were replaced in a loop | T3 `standard` credits: new t3.micro had `CPUCreditBalance = 0`, throttled to 10% CPU; `dnf install docker` took > 4 min | `cpu_credits = "unlimited"`, grace period 300 s; boot now ~2 min |
| `no-healthy-targets` alarm in ALARM on an idle site | ALB metrics missing while idle were treated as breaching | `treat_missing_data = "notBreaching"` |
| Homepage showed `local-dev` on the first view after boot | Per-bundle metadata cache + 1 s IMDS timeout during cold start | Shared `globalThis` cache, warm-up in `instrumentation.ts`, 2 s timeout |
| ~3.5 min outage during the CPU-credit rollout | Cancelling a stuck instance refresh left 2 instances for desired 1; Auto Scaling terminated the healthy one (oldest launch template) | Lesson: fix boot problems before rolling out; the stuck refresh no longer occurs |

## Observation

Between ~19:05 and ~19:16 almost no requests reached the ALB (k6 sent 371 instead of ~750 requests, with no
errors). This is consistent with the local PC pausing (sleep or network interruption), not an AWS fault. Scale-in
had already met its condition and proceeded normally.

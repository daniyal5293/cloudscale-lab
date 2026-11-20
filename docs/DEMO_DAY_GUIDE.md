# CloudScale Lab: Demo Day Guide (4 December 2026)

Everything the team needs to redeploy, run the live demo, and read the dashboards.
Slot: **10 min presentation + demo**, then a **5 min viva**. Deck: [CloudScale_Lab_Presentation.pptx](CloudScale_Lab_Presentation.pptx)
(speaker notes say who presents what).

---

## 1. Redeploy (do it the day before: 3 December)

```powershell
cd c:\Users\DELL\Desktop\devops-project\infrastructure\terraform
aws sts get-caller-identity            # credentials OK? should show ...:user/cloudscale-deployer
terraform plan -out tfplan             # expect: 28 to add, 0 to change, 0 to destroy
terraform apply tfplan                 # about 3-4 minutes
terraform output -raw alb_url          # the NEW app URL (it changes on every redeploy)
```

Wait about 2 minutes for the first instance to boot, then open the URL. A page showing an instance ID like `i-0…`
means it works. Then either keep it running overnight (about $1.40) or destroy it and apply again on the morning of
the 4th (at least 1 hour before class).

Every link you need is in `terraform output`:

| Output | Opens |
|---|---|
| `alb_url` | The app |
| `dashboard_url` | CloudWatch dashboard |
| `asg_console_url` | Auto Scaling Group → Activity tab (scaling events) |

---

## 2. What `SCENARIO=demo` does

k6 runs for **28 minutes**: 2 min ramp-up to 30 virtual users, **25 min steady at about 25 requests/second**, 1 min
ramp-down. It demonstrates **scale-out and load distribution**, **not scale-in**.

| Time after starting k6 | What happens |
|---|---|
| 0–2 min | Load ramps up; 1 instance handles everything |
| ~2 min | Requests per target reaches about **1,480/min**, far above the 600 target |
| ~7–8 min | CloudWatch alarm → **desired capacity 1 → 3**; 2 new instances launch |
| ~9–10 min | New instances become **healthy**; load shared by 3 (about 500/min each) |
| 10–27 min | Steady state with 3 instances: **present during this window** |
| 28 min | k6 finishes |

**Start k6 10 minutes before your slot**, so it has already scaled when you begin.

**Scale-in is not shown live.** It needs about 15 minutes of low traffic after the load ends. Show the recorded
scale-in on **slide 7** instead. To see it after class, run `SCENARIO=scalein` (25 min of light traffic). Don't
rely on zero traffic: with no requests the ALB may publish no data, and the group can stay at 3 instances until you
destroy.

### Does it go to 2 or straight to 3?

**Straight to 3 in one step**, measured on 20 Nov. Target tracking computes the whole step at once:

```
desired = ceil( current instances × actual requests per target ÷ target )
        = ceil( 1 × 1,485 ÷ 600 ) = ceil(2.47) = 3
```

| Load on 1 instance (requests/min) | Calculation | New desired |
|---|---|---|
| up to 600 | no alarm | stays 1 |
| 601 – 1,200 | ceil(1.01 … 2.0) | **2** |
| 1,201 – 1,800+ | ceil(2.01 … 3.0) | **3** (capped by max = 3) |

The demo load (about 1,480/min) lands in the "3" row. If the classroom internet is slow, k6 sends fewer requests, and
the group may scale to **2** first and add the third later. That's still correct behaviour, and worth explaining.

What we saw on 20 Nov:

| Event | Time | Detail |
|---|---|---|
| Desired 1 → 3 | 18:46:02 | Both new instances launched at the same second |
| 2nd instance healthy | 18:48:08 | Healthy hosts 1 → 2 |
| 3rd instance healthy | 18:48:28 | Healthy hosts 2 → 3 (20 s later) |
| Scale-in 3 → 2 | 19:09:02 | Scale-in removes instances **one step at a time** |
| Scale-in 2 → 1 | 19:10:08 | Back to minimum |

So scale-out jumps (1 → 3), the *healthy* count climbs 1 → 2 → 3 as each instance finishes booting, and scale-in steps
down gradually (3 → 2 → 1) to avoid removing too much capacity at once.

---

## 3. How traffic is distributed (load-balancing algorithm)

- **Algorithm: round robin.** This is set in `infrastructure/terraform/load-balancer.tf` as
  `load_balancing_algorithm_type = "round_robin"`. The ALB sends each new request to the next healthy target in turn.
- **Per request, not per connection.** The ALB is a Layer-7 (HTTP) load balancer, so even requests over one browser
  connection can go to different instances.
- **Only healthy targets** receive traffic (health check `GET /api/health` every 15 s; 2 passes = healthy).
- **Cross-zone load balancing is always on** for ALBs: the load is spread evenly over *instances*, not just over the
  two Availability Zones.
- **No sticky sessions:** the app is stateless, so any instance can answer any request.
- Measured result: with 3 healthy instances, k6 got **17–25 responses from each of the 3 instances** (60 requests per
  virtual user), roughly one third each.
- Alternatives AWS offers (not used): **least outstanding requests** (send to the least busy target; better when
  requests have very different durations) and **weighted random** (with anomaly mitigation).

---

## 4. Demo-day run-sheet

**15 minutes before:** open 4 browser tabs.

| Tab | What |
|---|---|
| 1 | The app (`alb_url`) |
| 2 | CloudWatch dashboard (`dashboard_url`), time range **1h**, auto-refresh **10s** |
| 3 | Auto Scaling Activity tab (`asg_console_url`) |
| 4 | EC2 → **Target groups** → `cloudscale-lab-demo-tg` → **Targets** tab |

**10 minutes before**, on a laptop that is **plugged in, with sleep turned off** (bring a mobile hotspot as backup):

```powershell
cd c:\Users\DELL\Desktop\devops-project
k6 run -e BASE_URL=<paste alb_url> -e SCENARIO=demo load-testing/k6-load-test.js
# optional live text view in a second terminal:
.\scripts\watch-scaling.ps1
```

**Presentation flow**

| Time | Who | What |
|---|---|---|
| 0:00–4:30 | Members 1–3 | Slides 1–5 |
| 4:30–9:00 | Member 4 | Slide 6, then the live demo below |
| 9:00–10:00 | Member 5 | Slides 7–8. Slide 7 is the backup evidence if the live demo fails |
| Viva | Everyone | [PROJECT_DEEP_DIVE.md](PROJECT_DEEP_DIVE.md), README troubleshooting table, this guide |

**Live demo order (about 4 min)**

| # | Tab | Point at | Say |
|---|---|---|---|
| 1 | k6 terminal | It is running | "This laptop sends about 25 requests per second to our load balancer." |
| 2 | Dashboard | **Requests per target vs target**: line went above the orange 600 line, then came back down | "This is the trigger: each server got about 1,480 requests per minute, 2.5× our target." |
| 3 | Dashboard | **Auto Scaling Group capacity**: Desired 1 → 3 | "AWS decided by itself that we needed 3 servers." |
| 4 | Activity tab | Two "Launching a new EC2 instance" rows; open one to show the cause | "Launched because the target-tracking alarm fired." |
| 5 | Targets tab | 3 targets, all **healthy**, in 2 AZs | "Only healthy servers receive traffic." |
| 6 | The app | **Send requests** in the distribution tester: 3 different instance IDs | "Round robin: requests rotate across all three servers." |
| 7 | Dashboard | **Requests and errors**: 5XX = 0 | "No failed requests while scaling." |

---

## 5. Reading the dashboards

One story: **cause → decision → action → result.**

| Role | Metric | Dashboard panel | Meaning | Look for |
|---|---|---|---|---|
| **Cause** | `RequestCountPerTarget` | Requests per target (scaling metric) vs target | Requests each server got in the last minute. **The number Auto Scaling watches** | Above the orange 600 line → scale-out coming; back near 600 → enough servers |
| **Decision** | `GroupDesiredCapacity` | Auto Scaling Group capacity, "Desired" | How many servers AWS **wants** | Steps 1 → 3 |
| **Action** | `GroupPendingInstances` / `GroupInServiceInstances` | Same panel, "Pending (booting)" / "In service" | Booting vs running | Pending appears briefly; In service rises to 3 |
| **Result** | `HealthyHostCount` | Target health, green line | Servers the **load balancer** sends traffic to | Reaches 3 about 2 min after launch; red Unhealthy ends at 0 |

**Desired → In service → Healthy:** the plan, the machine running, the app answering health checks. All three reach 3,
in that order, a minute or two apart.

Supporting panels:

| Panel | Meaning | Healthy value |
|---|---|---|
| **Current state** (top row of big numbers) | In-service, desired, healthy, unhealthy, requests/min | e.g. 3 / 3 / 3 / 0 under load |
| **Target response time** | Time the **server** took to answer; p95 = 95% of requests were faster | A few ms (0.002–0.007 s) |
| **Requests and errors** | Total, 2XX success, 5XX errors from targets and from the ALB | 5XX = 0 |
| **EC2 CPU / Network** | How busy the servers are (5-minute data, so it lags) | Rises with load, then shared by 3 |
| **Alarms** | Unhealthy targets, no healthy targets, 5XX, p95 latency | All **OK** |

In the **AWS console** (Auto Scaling Group page):
- **Activity** tab: each launch/terminate, with the *cause* (which alarm, desired capacity from X to Y).
- **Instance management** tab: each instance's AZ, lifecycle (`Pending` / `InService`) and health.
- **Details** tab: min 1 / desired / max 3.

---

## 6. After the presentation: clean up

```powershell
cd c:\Users\DELL\Desktop\devops-project\infrastructure\terraform
terraform destroy                      # review, type "yes" (about 3-5 min)
cd ..\..
.\scripts\verify-cleanup.ps1           # every line should say "none"
```

Check **Billing → Bills** the next day.

# CloudScale Lab: Cost Estimate

> **Read this before running `terraform apply`.**
> This project is **not "lifetime free"**. Every resource below is billed per hour or per second while it exists.
> On the AWS **Free plan** these charges are paid from your **promotional credits**. When the credits or the
> Free-plan period run out, the account must be upgraded or it is closed. Either way, resources left running
> cost real money or credits.

All prices are **AWS On-Demand list prices for `us-east-1` (N. Virginia), Linux, as published by AWS** at the time
of writing. **Re-check them in the [AWS Pricing Calculator](https://calculator.aws/) before approving a deployment**,
because prices change and other regions differ.

---

## 1. Resource-by-resource estimate

| # | Resource (Terraform) | Billing unit | Price | Count (min → max) | $/hour (1 instance) | $/hour (3 instances) |
|---|---|---|---|---|---|---|
| 1 | Application Load Balancer (`aws_lb.app`) | ALB-hour | ~$0.0225 | 1 | 0.0225 | 0.0225 |
| 2 | ALB capacity units (LCU) | LCU-hour | ~$0.008 | demo traffic < 1 LCU | ≤ 0.008 | ≤ 0.008 |
| 3 | Public IPv4 addresses on the ALB (one per AZ) | IP-hour | $0.005 | 2 | 0.010 | 0.010 |
| 4 | EC2 `t3.micro` (launched by the ASG) | instance-hour (per-second billing) | ~$0.0104 | 1 → 3 | 0.0104 | 0.0312 |
| 5 | Public IPv4 on each EC2 instance | IP-hour | $0.005 | 1 → 3 | 0.005 | 0.015 |
| 6 | EBS gp3 root volume, 8 GiB each | GB-month | $0.08 | 8 → 24 GiB | ~0.0009 | ~0.0026 |
| 7 | CloudWatch dashboard (1) | dashboard-month | free up to 3 dashboards (≤ 50 metrics each)\* | 1 | 0 | 0 |
| 8 | CloudWatch alarms (4 + 2 managed by target tracking) | alarm-month | free up to 10 standard alarms\* | 6 (8 with CPU policy) | 0 | 0 |
| 9 | ALB / Auto Scaling / EC2 basic metrics | n/a | included at no charge | n/a | 0 | 0 |
| 10 | Data transfer out to the internet | GB | first 100 GB/month free (all services combined)\* | ~10–20 MB per test | ~0 | ~0 |
| 11 | VPC, subnets, route table, IGW, security groups | n/a | no charge | n/a | 0 | 0 |
| 12 | IAM role, instance profile | n/a | no charge | n/a | 0 | 0 |
| 13 | Launch template, Auto Scaling Group, scaling policy | n/a | no charge (you pay for the instances) | n/a | 0 | 0 |
| 14 | SSM Session Manager (EC2) | n/a | no additional charge | n/a | 0 | 0 |
| 15 | SNS e-mail (only if `alarm_email` is set) | notification | first 1,000 e-mails/month free\* | a few | 0 | 0 |
| | **Total** | | | | **≈ $0.057/h** | **≈ $0.090/h** |

\* These are AWS "always free" allowances. They are shared across your whole account and are subject to AWS's current terms;
verify them on your Billing → Free Tier page.

### What this project deliberately does NOT create

| Avoided resource | Typical cost if it were used |
|---|---|
| NAT Gateway | ~$0.045/h (~$33/month) + $0.045/GB processed |
| Elastic IPs | $0.005/h each (+ idle charges) |
| VPC interface endpoints (e.g. for SSM) | ~$0.01/h per endpoint per AZ |
| RDS / managed database | from ~$0.017/h + storage |
| EKS control plane | $0.10/h |
| EC2 detailed monitoring | ~$2.10 per instance-month (7 metrics) |

---

## 2. Scenario estimates

| Scenario | Assumptions | Estimated cost |
|---|---|---|
| **1-hour test** | ALB for 1 h; 1 instance all hour; 2 extra instances for ~30 min during the spike | **≈ $0.06 – $0.09** |
| **3-hour demonstration** | ALB for 3 h; 1 instance throughout; 2 extra instances for ~1 h in total | **≈ $0.18 – $0.27** |
| **Forgotten, running continuously (1 instance)** | 730 h/month | **≈ $41 / month** |
| **Forgotten, stuck at max (3 instances)** | 730 h/month | **≈ $65 / month** |

Notes:
- **ALB partial hours may be billed as full hours**, so a 10-minute test still costs about one ALB-hour.
- EC2 Linux is billed per second (60-second minimum per instance launch).
- Each scale-out → scale-in cycle launches new instances, which adds a little EC2 time. It's negligible at this size.
- k6 runs on **your own computer**, so there's no load-generator instance to pay for.

## 3. Which resources consume credits?

On the Free plan, **every billable line above (1–6) is paid from credits** while they exist. The rows marked
"always free" (7–15) consume nothing as long as you stay inside those allowances. The main credit consumers, in
order:

1. **The ALB itself** (≈ 60% of the hourly cost at 1 instance). It is billed even with zero traffic.
2. **Public IPv4 addresses** (2 on the ALB + 1 per instance). AWS charges for every public IPv4 address, in use or not.
3. **EC2 instances**, which scale with the Auto Scaling Group's size, capped at `asg_max_size = 3`.
4. **EBS volumes**, which are tiny and deleted with the instance (`delete_on_termination = true`).

## 4. Biggest cost risks and their mitigations

| Risk | Mitigation built into this project |
|---|---|
| Forgetting to run `terraform destroy` | Cleanup procedure + `scripts/verify-cleanup.ps1`; set a Budget alert (below) |
| Runaway scale-out | `asg_max_size` hard-capped at 3 (validation rejects > 4) |
| T3 Unlimited surplus CPU credits ($0.05 per vCPU-hour above the 10% baseline) | Accepted on purpose: `standard` mode left new instances throttled and unable to boot in time. Expect about $0.005 per instance launch and a few cents per load-test session. Worst case is about $0.09/h per instance at 100% CPU, capped by `asg_max_size = 3` |
| Paid detailed monitoring | `detailed_monitoring = false` by default |
| Extra dashboards/alarms beyond free allowance | 1 dashboard, 4 alarms (+2 managed) |
| NAT Gateway / endpoints | Not used; public subnets with SG restrictions instead |
| Crash-looping instances (bad image) | ELB health checks replace them, but each replacement is a new billed launch. Check the image *before* applying (`preflight-check.ps1 -Image ...`) |

## 5. Checking credits, Free-plan time and billing (AWS Console)

1. **Account plan and credits:** sign in → search **"Billing and Cost Management"** → **Home**. Free-plan
   accounts show a widget with **credits remaining** and **days remaining** on the plan. Under
   **Billing and Cost Management → Credits** you'll find each credit's amount, remaining balance and expiry date.
2. **Free Tier usage:** Billing and Cost Management → **Free Tier**. This shows usage against always-free allowances,
   for example CloudWatch alarms and data transfer.
3. **Current charges:** Billing and Cost Management → **Bills** (month-to-date, per service) and
   **Cost Explorer** (daily view; data appears with up to 24 h delay).
4. **Budget alert (recommended):** Billing and Cost Management → **Budgets** → *Create budget* →
   *Use a template* → **Zero spend budget** (alerts as soon as spend exceeds $0.01) or **Monthly cost budget**
   with e.g. **$5**. Enter your e-mail. AWS documents budgets with notifications (without automated
   *actions*) as free of charge, but verify this on the AWS Budgets pricing page. Note that budgets track
   **charges**: on the Free plan, usage covered by credits may not trigger a "zero spend" budget, so also
   watch the credits widget.
5. **Plan expiry:** the Free plan ends after a fixed period or when credits are used up, whichever is first. AWS
   shows the exact date in the Free-plan widget. Never click **"Upgrade plan"** unless you intend to.

## 6. Cleanup (stops all charges from this project)

```powershell
cd infrastructure/terraform
terraform destroy          # review the list, type "yes"
cd ../..
./scripts/verify-cleanup.ps1
```

Then check **Billing → Bills** the next day to confirm no new EC2/ELB charges accrue.

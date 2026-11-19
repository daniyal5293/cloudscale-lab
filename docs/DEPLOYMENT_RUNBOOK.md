# CloudScale Lab: Deployment Runbook

The exact, ordered steps to go from "code on my laptop" to "demo running on AWS" and back to "nothing billed".

> **Approval gate:** Steps 1–6 create nothing on AWS. Step 7 (`terraform apply`) is the first step that
> creates billable resources. Do it only after reviewing the plan output and [COST_ESTIMATE.md](COST_ESTIMATE.md).

---

## Step 1: Account eligibility checklist (AWS Console, ~5 min)

| ✔ | Check | Where |
|---|---|---|
| ☐ | Account plan is **Free** (not upgraded), and you know the **plan end date** | Billing and Cost Management → Home (Free-plan widget) |
| ☐ | **Credits remaining** comfortably exceed the demo estimate (< $1) | Billing and Cost Management → Credits |
| ☐ | A **Budget alert** exists (zero-spend or $5 monthly) with your e-mail | Billing and Cost Management → Budgets |
| ☐ | Region selector set to **US East (N. Virginia) us-east-1** | Top-right of the console |
| ☐ | EC2, EC2 Auto Scaling, Elastic Load Balancing, CloudWatch, Systems Manager open without "not available on your plan" errors | Open each service page once |
| ☐ | `t3.micro` is listed as **Free tier eligible** | EC2 → Instance types → filter "Free tier eligible" (or run the preflight script) |
| ☐ | You are **not** using the root user for CLI access | IAM → Users |

**Never click "Upgrade plan" during this project.**

## Step 2: Create a deployment identity (IAM, ~10 min)

Do not create access keys for the root user.

1. IAM → **Users** → *Create user* → name `cloudscale-deployer` → no console access needed.
2. *Attach policies directly* → *Create policy* → JSON → paste [`iam/deployer-policy.json`](iam/deployer-policy.json).
   This policy is limited to `us-east-1`, can only create IAM roles named `cloudscale-lab-*`, and can only pass
   that role to EC2. Name it `CloudScaleLabDeployer` and attach it to the user.
3. User → **Security credentials** → *Create access key* → use case **Command Line Interface (CLI)**.
4. On your PC:
   ```powershell
   aws configure
   # AWS Access Key ID:     (paste)
   # AWS Secret Access Key: (paste; it's stored in %USERPROFILE%\.aws\credentials, never in this repo)
   # Default region name:   us-east-1
   # Default output format: json
   aws sts get-caller-identity   # should show ...:user/cloudscale-deployer
   ```
5. **After the project is graded, delete the access key** (IAM → user → Security credentials).

> Alternative without long-lived keys: IAM Identity Center + `aws configure sso`. It's more secure, with a
> slightly longer setup.

## Step 3: Publish the container image (GitHub, ~10 min)

1. Create a **public** GitHub repository named **`cloudscale-lab`**.
2. Push this project (`main` branch). The **CI** workflow lints, builds, smoke-tests and pushes
   `ghcr.io/<your-username>/cloudscale-lab:latest` and `:sha-<7 chars>`.
3. Make the package public: GitHub → your profile → **Packages** → `cloudscale-lab` → **Package settings** →
   *Change visibility* → **Public**. New GHCR packages start **private**, and EC2 instances pull anonymously, so a
   private package makes every instance fail its health check.
4. Note the immutable tag from the workflow summary, e.g. `ghcr.io/<user>/cloudscale-lab:sha-1a2b3c4`.

## Step 4: Pre-flight checks (read-only)

```powershell
./scripts/preflight-check.ps1 -Image ghcr.io/<user>/cloudscale-lab:sha-1a2b3c4
```
All lines should be `[ OK ]`. Pay special attention to:
- the **vCPU quota**: 3 × t3.micro needs 6 vCPUs, and new accounts sometimes have less. Request an increase in
  Service Quotas if needed (this is free);
- **image pullable anonymously**, which shows the package really is public.

## Step 5: Configure Terraform variables

```powershell
cd infrastructure/terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # git-ignored
notepad terraform.tfvars                              # set container_image to your sha- tag
```

## Step 6: Plan and review (read-only)

```powershell
terraform init
terraform validate
terraform plan -out tfplan
```

Review the plan. You should see **28 resources to add, 0 to change, 0 to destroy** with default variables
(30 if `alarm_email` is set, 29 with `enable_cpu_policy = true`):

| Group | Resources |
|---|---|
| Networking (7) | 1 VPC, 1 internet gateway, 2 subnets, 1 route table, 2 route-table associations |
| Security (10) | 2 security groups, 5 SG rules\*, 1 IAM role, 1 policy attachment, 1 instance profile |
| Load balancing (3) | 1 ALB, 1 target group, 1 listener |
| Compute (3) | 1 launch template, 1 Auto Scaling Group, 1 scaling policy |
| Monitoring (5) | 1 dashboard, 4 alarms |

\* `alb_http` creates one rule per CIDR in `allowed_http_cidrs` (default: 1).

**Red flags: stop and ask if the plan contains** `aws_nat_gateway`, `aws_eip`, `aws_db_instance`,
`aws_vpc_endpoint`, `aws_eks_*`, or any `destroy` you did not expect.

## Step 7: Apply ⚠ creates billable resources (requires explicit approval)

```powershell
terraform apply tfplan
```
This takes about 3–5 minutes (the ALB is the slowest). Note the outputs:

```powershell
terraform output
```

## Step 8: Validate the deployment

```powershell
$alb = terraform output -raw alb_url
curl.exe -s "$alb/api/health"      # {"status":"ok",...}
curl.exe -s "$alb/api/instance"    # instanceId "i-0..." and an AZ like "us-east-1a"
Start-Process $alb                  # open the web UI

aws elbv2 describe-target-health --target-group-arn (terraform output -raw target_group_arn) `
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table

Start-Process (terraform output -raw dashboard_url)
```

If the target shows `unhealthy` or `initial` for more than ~5 minutes, see *Troubleshooting* in the README.

Optional: open a shell on an instance without SSH:
EC2 console → instance → **Connect** → **Session Manager** → *Connect*, then:
```bash
sudo tail -n 50 /var/log/cloudscale-userdata.log
sudo docker ps
sudo docker logs cloudscale --tail 20
```

## Step 9: Demonstration script (~45–60 min)

Use two terminals and the CloudWatch dashboard (time range **1h**, auto-refresh **10s**).

| Time | Terminal 1 | Terminal 2 / browser | What to point out |
|---|---|---|---|
| 0:00 | `./scripts/watch-scaling.ps1` | Dashboard + web UI | 1 instance, 1 healthy target |
| 0:02 | `k6 run -e BASE_URL=$alb -e SCENARIO=normal load-testing/k6-load-test.js` | | ~180 req/min, below the target (600). **No scaling.** |
| 0:08 | `k6 run -e BASE_URL=$alb -e SCENARIO=spike load-testing/k6-load-test.js` | | RequestCountPerTarget crosses the orange line |
| ~0:12 | | Watch ASG Activity tab | Desired → 3; Pending instances; new targets `initial` → `healthy` |
| ~0:17 | `./scripts/check-distribution.ps1` (or web UI tester) | | Responses from **2–3 different instance IDs** in 2 AZs |
| 0:23 | `k6 run -e BASE_URL=$alb -e SCENARIO=scalein load-testing/k6-load-test.js` | | Low trickle; after ~15 min below target the ASG terminates instances |
| ~0:45 | | Dashboard | Desired back to 1; targets `draining` → removed |

Optional extra demo of **unhealthy-instance replacement**: in Session Manager on one instance run
`sudo docker stop cloudscale`. Within ~30 s the target turns `unhealthy`, the *unhealthy-targets* alarm fires,
the ALB stops sending it traffic, and Auto Scaling terminates and replaces it.

## Step 10: Cleanup ⚠ (same day!)

```powershell
cd infrastructure/terraform
terraform destroy            # type "yes"; about 3–5 minutes
cd ../..
./scripts/verify-cleanup.ps1 # every line should say "none"
```

Then:
- Billing → Bills next day: no growing EC2/ELB line items.
- If you are completely finished, delete the IAM access key from Step 2.
- `terraform.tfstate` stays on your PC (git-ignored). Keep it until destroy has succeeded.

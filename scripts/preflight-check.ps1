<#
.SYNOPSIS
  READ-ONLY readiness checks before deploying CloudScale Lab. Creates nothing.

.DESCRIPTION
  Verifies local tools, the AWS identity in use (account ID only, never keys),
  region, free-tier-eligible instance types, the EC2 vCPU quota, Availability
  Zones, and that the container image can be pulled anonymously from GHCR.

  It CANNOT tell you whether your account is on the Free or Paid plan, or how
  many credits remain. Check that in the AWS Console (see docs/DEPLOYMENT_RUNBOOK.md).

.EXAMPLE
  ./scripts/preflight-check.ps1 -Image ghcr.io/<user>/cloudscale-lab:latest
#>
param(
  [string]$Region = "us-east-1",
  [string]$InstanceType = "t3.micro",
  [int]$MaxInstances = 3,
  [string]$Image = ""
)

$ErrorActionPreference = "Continue"
$script:failures = 0

function Write-Result([string]$Name, [bool]$Ok, [string]$Detail) {
  $mark = if ($Ok) { "[ OK ]" } else { "[FAIL]"; $script:failures++ }
  $color = if ($Ok) { "Green" } else { "Red" }
  Write-Host ("{0} {1,-34} {2}" -f $mark, $Name, $Detail) -ForegroundColor $color
}

function Write-Info([string]$Name, [string]$Detail) {
  Write-Host ("[INFO] {0,-34} {1}" -f $Name, $Detail) -ForegroundColor Cyan
}

Write-Host "`nCloudScale Lab: pre-flight checks (read-only)`n" -ForegroundColor Yellow

# ---- Local tools ----
foreach ($tool in "terraform", "aws", "docker", "k6") {
  $cmd = Get-Command $tool -ErrorAction SilentlyContinue
  Write-Result "Tool: $tool" ([bool]$cmd) $(if ($cmd) { $cmd.Source } else { "not found on PATH" })
}

# ---- AWS identity (account ID + ARN only) ----
$identityJson = aws sts get-caller-identity --output json 2>$null
if ($LASTEXITCODE -eq 0) {
  $identity = $identityJson | ConvertFrom-Json
  Write-Result "AWS credentials" $true "account $($identity.Account)"
  Write-Info "Caller ARN" $identity.Arn
  if ($identity.Arn -match ":root$") {
    Write-Result "Not using root user" $false "create an IAM/Identity Center user; never use root access keys"
  }
} else {
  Write-Result "AWS credentials" $false "run 'aws configure' (or 'aws configure sso') first"
  Write-Host "`nRemaining AWS checks skipped.`n"
  exit 1
}

$configuredRegion = aws configure get region 2>$null
Write-Info "CLI default region" $(if ($configuredRegion) { $configuredRegion } else { "(not set)" })
Write-Info "Region checked" $Region

# ---- Instance type eligibility ----
$eligible = aws ec2 describe-instance-types --region $Region `
  --filters Name=free-tier-eligible,Values=true `
  --query "InstanceTypes[].InstanceType" --output json 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -eq 0) {
  Write-Info "Free-tier-eligible types" (($eligible | Sort-Object) -join ", ")
  Write-Result "$InstanceType is free-tier eligible" ($eligible -contains $InstanceType) "per EC2 API in $Region"
} else {
  Write-Result "Query instance types" $false "ec2:DescribeInstanceTypes failed (permissions?)"
}

$offered = aws ec2 describe-instance-type-offerings --region $Region --location-type availability-zone `
  --filters Name=instance-type,Values=$InstanceType --query "InstanceTypeOfferings[].Location" --output json 2>$null | ConvertFrom-Json
Write-Result "$InstanceType offered in AZs" ($offered.Count -ge 2) (($offered | Sort-Object) -join ", ")

# ---- vCPU quota (Running On-Demand Standard instances) ----
$needed = $MaxInstances * 2   # t3.micro = 2 vCPUs
$quota = aws service-quotas get-service-quota --region $Region --service-code ec2 --quota-code L-1216C47A `
  --query "Quota.Value" --output text 2>$null
if ($LASTEXITCODE -eq 0 -and $quota) {
  Write-Result "On-Demand vCPU quota" ([double]$quota -ge $needed) "quota $quota vCPU, need $needed for $MaxInstances x $InstanceType"
} else {
  Write-Info "On-Demand vCPU quota" "could not read (servicequotas permission?); check Service Quotas console"
}

# ---- Availability Zones ----
$azs = aws ec2 describe-availability-zones --region $Region --filters Name=opt-in-status,Values=opt-in-not-required `
  --query "AvailabilityZones[?State=='available'].ZoneName" --output json 2>$null | ConvertFrom-Json
Write-Result "At least 2 AZs available" ($azs.Count -ge 2) (($azs | Select-Object -First 2) -join ", ")

# ---- Existing project resources (avoid duplicate deployments) ----
$existing = aws elbv2 describe-load-balancers --region $Region `
  --query "LoadBalancers[?starts_with(LoadBalancerName,'cloudscale-lab')].LoadBalancerName" --output json 2>$null | ConvertFrom-Json
Write-Result "No existing CloudScale ALB" (-not $existing) $(if ($existing) { "found: $($existing -join ', ')" } else { "clean" })

# ---- GHCR image is publicly pullable ----
if ($Image) {
  # Use an empty, temporary Docker config so the pull is anonymous (like on EC2)
  # without logging you out of your own registries.
  $anonConfig = Join-Path ([IO.Path]::GetTempPath()) "cloudscale-anon-docker"
  New-Item -ItemType Directory -Force $anonConfig | Out-Null
  docker --config $anonConfig pull --platform linux/amd64 $Image *> $null
  Write-Result "Image pullable anonymously" ($LASTEXITCODE -eq 0) $Image
  Remove-Item -Recurse -Force $anonConfig -ErrorAction SilentlyContinue
} else {
  Write-Info "Image check" "skipped (pass -Image ghcr.io/<user>/cloudscale-lab:<tag>)"
}

Write-Host ""
if ($script:failures -eq 0) {
  Write-Host "All checks passed. Still verify plan, credits and Budgets in the Billing console." -ForegroundColor Green
} else {
  Write-Host "$($script:failures) check(s) failed. Fix them before 'terraform plan'." -ForegroundColor Red
  exit 1
}

<#
.SYNOPSIS
  Sends N requests to /api/instance and counts which EC2 instance answered each one.
  Demonstrates ALB load distribution (Scenario D). Read-only; makes only HTTP GETs.

.EXAMPLE
  ./scripts/check-distribution.ps1 -Url http://cloudscale-lab-demo-alb-123.us-east-1.elb.amazonaws.com -Count 60
.EXAMPLE
  # Reads the ALB URL from Terraform outputs
  ./scripts/check-distribution.ps1
#>
param(
  [string]$Url = "",
  [int]$Count = 60
)

if (-not $Url) {
  $tfDir = Join-Path $PSScriptRoot "..\infrastructure\terraform"
  $Url = terraform -chdir="$tfDir" output -raw alb_url 2>$null
  if (-not $Url) { Write-Error "Pass -Url or run after 'terraform apply' so the alb_url output exists."; exit 1 }
}
$Url = $Url.TrimEnd("/")

Write-Host "Sending $Count requests to $Url/api/instance ...`n"
$results = @()
$errors = 0
for ($i = 1; $i -le $Count; $i++) {
  try {
    $r = Invoke-RestMethod -Uri "$Url/api/instance" -Headers @{ "Cache-Control" = "no-cache" } -TimeoutSec 5
    $results += [pscustomobject]@{ InstanceId = $r.instanceId; AZ = $r.availabilityZone }
  } catch {
    $errors++
  }
}

$results | Group-Object InstanceId | Sort-Object Count -Descending | ForEach-Object {
  $pct = [math]::Round(100 * $_.Count / [math]::Max(1, $results.Count), 1)
  [pscustomobject]@{
    InstanceId = $_.Name
    AZ         = $_.Group[0].AZ
    Requests   = $_.Count
    Percent    = "$pct %"
    Bar        = "#" * [math]::Ceiling($pct / 2)
  }
} | Format-Table -AutoSize

$distinct = ($results | Select-Object -ExpandProperty InstanceId -Unique).Count
Write-Host "Distinct instances: $distinct   Successful: $($results.Count)   Errors: $errors"
if ($distinct -le 1) {
  Write-Host "Only one instance answered. Before scale-out this is expected; after scale-out, wait until new targets are 'healthy'." -ForegroundColor Yellow
}

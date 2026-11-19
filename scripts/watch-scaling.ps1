<#
.SYNOPSIS
  Live, READ-ONLY view of Auto Scaling capacity, target health and recent
  scaling activities. Run it in a second terminal during k6 tests.

.EXAMPLE
  ./scripts/watch-scaling.ps1                 # names read from Terraform outputs
  ./scripts/watch-scaling.ps1 -IntervalSeconds 30
#>
param(
  [string]$AsgName = "",
  [string]$TargetGroupArn = "",
  [string]$Region = "us-east-1",
  [int]$IntervalSeconds = 20
)

$tfDir = Join-Path $PSScriptRoot "..\infrastructure\terraform"
if (-not $AsgName) { $AsgName = terraform -chdir="$tfDir" output -raw asg_name 2>$null }
if (-not $TargetGroupArn) { $TargetGroupArn = terraform -chdir="$tfDir" output -raw target_group_arn 2>$null }
if (-not $AsgName -or -not $TargetGroupArn) {
  Write-Error "Pass -AsgName and -TargetGroupArn, or run after 'terraform apply'."
  exit 1
}

while ($true) {
  $asg = (aws autoscaling describe-auto-scaling-groups --region $Region --auto-scaling-group-names $AsgName --output json | ConvertFrom-Json).AutoScalingGroups[0]
  $health = (aws elbv2 describe-target-health --region $Region --target-group-arn $TargetGroupArn --output json | ConvertFrom-Json).TargetHealthDescriptions
  $activities = (aws autoscaling describe-scaling-activities --region $Region --auto-scaling-group-name $AsgName --max-items 4 --output json | ConvertFrom-Json).Activities

  Clear-Host
  Write-Host "CloudScale Lab: scaling monitor   $(Get-Date -Format 'HH:mm:ss')   (Ctrl+C to stop)" -ForegroundColor Yellow
  Write-Host ("ASG {0}:  min {1} | desired {2} | max {3}" -f $AsgName, $asg.MinSize, $asg.DesiredCapacity, $asg.MaxSize) -ForegroundColor Cyan

  Write-Host "`nInstances (Auto Scaling view)"
  $asg.Instances | Select-Object InstanceId, AvailabilityZone, LifecycleState, HealthStatus | Format-Table -AutoSize | Out-String | Write-Host

  Write-Host "Targets (ALB view)"
  $health | ForEach-Object {
    [pscustomobject]@{
      InstanceId = $_.Target.Id
      State      = $_.TargetHealth.State
      Reason     = $_.TargetHealth.Reason
    }
  } | Format-Table -AutoSize | Out-String | Write-Host

  Write-Host "Recent scaling activities"
  $activities | ForEach-Object {
    "{0}  {1,-12} {2}" -f ([datetime]$_.StartTime).ToLocalTime().ToString("HH:mm:ss"), $_.StatusCode, $_.Description
  } | Write-Host

  Start-Sleep -Seconds $IntervalSeconds
}

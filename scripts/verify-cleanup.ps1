<#
.SYNOPSIS
  READ-ONLY check, run AFTER 'terraform destroy', that no CloudScale Lab
  resources are left running (and billing). Deletes nothing.

.EXAMPLE
  ./scripts/verify-cleanup.ps1
#>
param(
  [string]$Region = "us-east-1",
  [string]$Project = "cloudscale-lab"
)

$leftovers = 0
function Test-Leftover([string]$Name, $Items) {
  $list = @($Items | Where-Object { $_ })
  if ($list.Count -gt 0) {
    Write-Host ("[LEFT] {0,-26} {1}" -f $Name, ($list -join ", ")) -ForegroundColor Red
    $script:leftovers += $list.Count
  } else {
    Write-Host ("[ OK ] {0,-26} none" -f $Name) -ForegroundColor Green
  }
}

Write-Host "`nCloudScale Lab: post-destroy verification in $Region`n" -ForegroundColor Yellow

Test-Leftover "EC2 instances" (aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Project,Values=$Project" "Name=instance-state-name,Values=pending,running,stopping,stopped" `
    --query "Reservations[].Instances[].InstanceId" --output json | ConvertFrom-Json)

Test-Leftover "Auto Scaling groups" (aws autoscaling describe-auto-scaling-groups --region $Region `
    --query "AutoScalingGroups[?starts_with(AutoScalingGroupName,'$Project')].AutoScalingGroupName" --output json | ConvertFrom-Json)

Test-Leftover "Load balancers" (aws elbv2 describe-load-balancers --region $Region `
    --query "LoadBalancers[?starts_with(LoadBalancerName,'$Project')].LoadBalancerName" --output json | ConvertFrom-Json)

Test-Leftover "Target groups" (aws elbv2 describe-target-groups --region $Region `
    --query "TargetGroups[?starts_with(TargetGroupName,'$Project')].TargetGroupName" --output json | ConvertFrom-Json)

Test-Leftover "EBS volumes" (aws ec2 describe-volumes --region $Region `
    --filters "Name=tag:Project,Values=$Project" --query "Volumes[].VolumeId" --output json | ConvertFrom-Json)

Test-Leftover "Elastic IPs (any)" (aws ec2 describe-addresses --region $Region `
    --query "Addresses[].PublicIp" --output json | ConvertFrom-Json)

Test-Leftover "Launch templates" (aws ec2 describe-launch-templates --region $Region `
    --filters "Name=tag:Project,Values=$Project" --query "LaunchTemplates[].LaunchTemplateName" --output json | ConvertFrom-Json)

Test-Leftover "VPCs" (aws ec2 describe-vpcs --region $Region `
    --filters "Name=tag:Project,Values=$Project" --query "Vpcs[].VpcId" --output json | ConvertFrom-Json)

Test-Leftover "CloudWatch alarms" (aws cloudwatch describe-alarms --region $Region `
    --alarm-name-prefix $Project --query "MetricAlarms[].AlarmName" --output json | ConvertFrom-Json)

Test-Leftover "CloudWatch dashboards" (aws cloudwatch list-dashboards --region $Region `
    --dashboard-name-prefix $Project --query "DashboardEntries[].DashboardName" --output json | ConvertFrom-Json)

Test-Leftover "NAT gateways (any)" (aws ec2 describe-nat-gateways --region $Region `
    --filter "Name=state,Values=pending,available" --query "NatGateways[].NatGatewayId" --output json | ConvertFrom-Json)

Write-Host ""
if ($leftovers -eq 0) {
  Write-Host "No CloudScale Lab resources found. Re-check Billing > Bills tomorrow (charges appear with a delay)." -ForegroundColor Green
} else {
  Write-Host "$leftovers resource(s) still exist. Re-run 'terraform destroy' or delete them in the console." -ForegroundColor Red
  exit 1
}

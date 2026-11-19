output "alb_url" {
  description = "Public URL of the application (via the load balancer)."
  value       = "http://${aws_lb.app.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  description = "ARN of the target group (use with: aws elbv2 describe-target-health)."
  value       = aws_lb_target_group.app.arn
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI used by the launch template."
  value       = data.aws_ami.al2023.id
}

output "availability_zones" {
  description = "Availability Zones used by the subnets and the ASG."
  value       = local.azs
}

output "dashboard_url" {
  description = "CloudWatch dashboard in the AWS Console."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${local.dashboard_name}"
}

output "asg_console_url" {
  description = "Auto Scaling Group in the AWS Console (see the Activity tab for scaling events)."
  value       = "https://${var.aws_region}.console.aws.amazon.com/ec2/home?region=${var.aws_region}#AutoScalingGroupDetails:id=${aws_autoscaling_group.app.name};view=activity"
}

output "k6_spike_command" {
  description = "Ready-to-run k6 command for the traffic-spike scenario."
  value       = "k6 run -e BASE_URL=http://${aws_lb.app.dns_name} -e SCENARIO=spike load-testing/k6-load-test.js"
}

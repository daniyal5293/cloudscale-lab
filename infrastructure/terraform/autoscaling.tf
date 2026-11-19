# ---------------------------------------------------------------------------
# EC2 Auto Scaling Group
# ---------------------------------------------------------------------------

resource "aws_autoscaling_group" "app" {
  name                = "${local.name}-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.public[*].id # spread across both AZs

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Instances are registered in / removed from the ALB target group automatically.
  target_group_arns = [aws_lb_target_group.app.arn]

  # Use the ALB health check (is the APP answering?), not just the EC2 status
  # check (is the VM running?). Failing instances get replaced.
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  # New instances are excluded from scaling metrics for this long while they boot.
  default_instance_warmup = var.instance_warmup

  # Publish group metrics (desired, in-service, pending...) to CloudWatch every
  # minute. Auto Scaling group metrics are free at 1-minute granularity.
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  # When the launch template changes (e.g. a new container image tag), replace
  # instances one at a time, launching the new one before terminating the old.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = var.instance_warmup
    }
  }

  wait_for_capacity_timeout = "10m"

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  lifecycle {
    # After creation the scaling policy owns desired capacity. Without this,
    # every `terraform apply` would reset it back to the initial value.
    ignore_changes = [desired_capacity]
  }
}

# ---------------------------------------------------------------------------
# Primary scaling policy: target tracking on ALBRequestCountPerTarget.
#
# "Keep the average number of requests per instance per minute near the target."
# AWS creates and manages two CloudWatch alarms for this policy:
#   * high alarm: 3 consecutive 1-minute datapoints above target  -> scale out
#   * low alarm:  15 consecutive 1-minute datapoints well below    -> scale in
# New capacity = ceil(current capacity * actual / target), bounded by min/max.
# ---------------------------------------------------------------------------

resource "aws_autoscaling_policy" "requests_per_target" {
  name                   = "${local.name}-alb-requests-per-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      # Format: app/<alb-name>/<id>/targetgroup/<tg-name>/<id>
      resource_label = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }

    target_value     = var.requests_per_target_per_minute
    disable_scale_in = false
  }

  # The target group must be attached to a listener before the metric exists.
  depends_on = [aws_lb_listener.http]
}

# ---------------------------------------------------------------------------
# OPTIONAL experiment: target tracking on average CPU utilization.
# Disabled by default (enable_cpu_policy = false). When enabled, Auto Scaling
# evaluates both policies and uses whichever asks for MORE capacity. It only
# scales in when BOTH policies agree. Adds 2 more managed alarms.
# Note: with basic monitoring, EC2 CPU is reported every 5 minutes, so this
# policy reacts more slowly than the request-count policy.
# ---------------------------------------------------------------------------

resource "aws_autoscaling_policy" "cpu" {
  count = var.enable_cpu_policy ? 1 : 0

  name                   = "${local.name}-cpu-utilization"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_percent
  }
}

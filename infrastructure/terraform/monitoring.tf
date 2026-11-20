# ---------------------------------------------------------------------------
# CloudWatch dashboard + alarms
#
# Uses only metrics AWS already publishes (no custom metrics, no agent):
#   AWS/ApplicationELB : free, 1-minute
#   AWS/AutoScaling    : free, 1-minute (enabled_metrics on the ASG)
#   AWS/EC2            : free basic monitoring, 5-minute
# Free allowances to verify for your account: 3 dashboards (up to 50 metrics each)
# and 10 standard-resolution alarms. This file creates 1 dashboard and 4 alarms;
# the target-tracking policy adds 2 managed alarms (4 with the CPU policy).
# ---------------------------------------------------------------------------

locals {
  dashboard_name = "${local.name}-dashboard"

  alb_dim = aws_lb.app.arn_suffix
  tg_dim  = aws_lb_target_group.app.arn_suffix
  asg_dim = aws_autoscaling_group.app.name

  alarm_actions = var.alarm_email == "" ? [] : [aws_sns_topic.alarms[0].arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      # ---- Row 0: title / explanation ----
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 3
        properties = {
          markdown = join("\n", [
            "# CloudScale Lab: Load Balancing & Auto Scaling",
            "**Scaling policy:** target tracking on `ALBRequestCountPerTarget` = **${var.requests_per_target_per_minute} req/target/min** · capacity **min ${var.asg_min_size} / max ${var.asg_max_size}** · ${var.instance_type} in ${var.aws_region}.",
            "During a traffic spike: *Requests per target* rises above the orange line → *Desired capacity* rises → *Pending* instances appear → *Healthy hosts* increases → requests per target fall back toward the target. Scale-in follows ~15 min after load drops.",
          ])
        }
      },

      # ---- Row 1: at-a-glance numbers ----
      {
        type   = "metric"
        x      = 0
        y      = 3
        width  = 24
        height = 4
        properties = {
          title     = "Current state"
          view      = "singleValue"
          region    = var.aws_region
          period    = 60
          stat      = "Maximum"
          sparkline = true
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg_dim, { label = "In-service instances" }],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", local.asg_dim, { label = "Desired capacity" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg_dim, "LoadBalancer", local.alb_dim, { label = "Healthy targets" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.tg_dim, "LoadBalancer", local.alb_dim, { label = "Unhealthy targets" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_dim, { label = "Requests / min", stat = "Sum" }],
          ]
        }
      },

      # ---- Row 2: the scaling story ----
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 7
        properties = {
          title  = "Requests per target (scaling metric) vs target"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCountPerTarget", "TargetGroup", local.tg_dim, "LoadBalancer", local.alb_dim, { label = "RequestCountPerTarget" }],
          ]
          annotations = {
            horizontal = [{ label = "Scaling target", value = var.requests_per_target_per_minute, color = "#ff7f0e" }]
          }
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 7
        properties = {
          title  = "Auto Scaling Group capacity"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", local.asg_dim, { label = "Desired" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg_dim, { label = "In service" }],
            ["AWS/AutoScaling", "GroupPendingInstances", "AutoScalingGroupName", local.asg_dim, { label = "Pending (booting)" }],
            ["AWS/AutoScaling", "GroupTerminatingInstances", "AutoScalingGroupName", local.asg_dim, { label = "Terminating" }],
          ]
          annotations = {
            horizontal = [
              { label = "Max size", value = var.asg_max_size, color = "#d62728" },
              { label = "Min size", value = var.asg_min_size, color = "#2ca02c" },
            ]
          }
          yAxis = { left = { min = 0, max = var.asg_max_size + 1 } }
        }
      },

      # ---- Row 3: load balancer health and performance ----
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Target health"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg_dim, "LoadBalancer", local.alb_dim, { label = "Healthy", stat = "Minimum", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.tg_dim, "LoadBalancer", local.alb_dim, { label = "Unhealthy", stat = "Maximum", color = "#d62728" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Target response time (seconds)"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_dim, { label = "Average", stat = "Average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_dim, { label = "p95", stat = "p95" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Requests and errors (per minute)"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_dim, { label = "Total requests" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", local.alb_dim, { label = "2XX from targets" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_dim, { label = "5XX from targets", color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb_dim, { label = "5XX from ALB (e.g. no healthy target)", color = "#9467bd" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },

      # ---- Row 4: EC2 resources (aggregated over the ASG, 5-minute basic monitoring) ----
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU utilization (%) across the ASG"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg_dim, { label = "Average", stat = "Average" }],
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg_dim, { label = "Maximum", stat = "Maximum" }],
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          title  = "EC2 network in/out (bytes) across the ASG"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/EC2", "NetworkIn", "AutoScalingGroupName", local.asg_dim, { label = "Network in" }],
            ["AWS/EC2", "NetworkOut", "AutoScalingGroupName", local.asg_dim, { label = "Network out" }],
          ]
          yAxis = { left = { min = 0 } }
        }
      },

      # ---- Row 5: alarm status ----
      {
        type   = "alarm"
        x      = 0
        y      = 26
        width  = 24
        height = 3
        properties = {
          title = "Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.no_healthy_hosts.arn,
            aws_cloudwatch_metric_alarm.target_5xx.arn,
            aws_cloudwatch_metric_alarm.high_latency.arn,
          ]
        }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Alarms (these notify only; scaling alarms are created by the scaling policy)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-targets"
  alarm_description   = "At least one target is failing the /api/health check."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { TargetGroup = local.tg_dim, LoadBalancer = local.alb_dim }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${local.name}-no-healthy-targets"
  alarm_description   = "No healthy targets: the site is down (ALB returns 503)."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = { TargetGroup = local.tg_dim, LoadBalancer = local.alb_dim }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  # ALB metrics are only published while requests flow. An idle site has NO
  # datapoints, which must not count as "down". If the site is down while
  # traffic flows, HealthyHostCount = 0 is published and the alarm fires.
  treat_missing_data = "notBreaching"
  alarm_actions      = local.alarm_actions
  ok_actions         = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.name}-target-5xx"
  alarm_description   = "Targets returned more than 5 HTTP 5XX responses per minute."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = local.alb_dim }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${local.name}-high-latency-p95"
  alarm_description   = "p95 target response time above ${var.latency_alarm_threshold_seconds}s for 3 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = local.alb_dim }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.latency_alarm_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------------------------------------------------------------------------
# Optional e-mail notifications (only created when alarm_email is set).
# AWS sends a confirmation e-mail that must be accepted before alerts arrive.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  count = var.alarm_email == "" ? 0 : 1
  name  = "${local.name}-alarms"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

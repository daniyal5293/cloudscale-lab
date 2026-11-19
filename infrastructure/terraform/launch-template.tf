# ---------------------------------------------------------------------------
# Launch template: the "blueprint" Auto Scaling uses for every new instance.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "app" {
  name_prefix = "${local.name}-lt-"
  description = "CloudScale Lab: AL2023 + Docker + app container"

  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  # IMDSv2 only. Hop limit 2 is required because the app runs inside a Docker
  # container (one extra network hop); with the default of 1 the token
  # response would never reach the container.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  # COST PROTECTION: T3 instances default to "unlimited" CPU credits, which can bill
  # surplus credits when the CPU is pushed hard during a load test. "standard"
  # throttles to baseline instead of charging.
  credit_specification {
    cpu_credits = "standard"
  }

  # Detailed (1-minute) EC2 monitoring is a paid feature; off by default.
  monitoring {
    enabled = var.detailed_monitoring
  }

  block_device_mappings {
    device_name = data.aws_ami.al2023.root_device_name

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true # outbound internet without a NAT Gateway
    security_groups             = [aws_security_group.app.id]
    delete_on_termination       = true
  }

  # replace() strips Windows CRLF line endings in case the template was checked
  # out on Windows; bash on Linux cannot run a script containing "\r".
  user_data = base64encode(replace(templatefile("${path.module}/templates/user-data.sh.tftpl", {
    container_image = var.container_image
    app_port        = var.app_port
    asg_min         = var.asg_min_size
    asg_desired     = var.asg_desired_capacity
    asg_max         = var.asg_max_size
    scaling_target  = var.requests_per_target_per_minute
    instance_type   = var.instance_type
    aws_region      = var.aws_region
  }), "\r\n", "\n"))

  # default_tags do not reach instances launched by Auto Scaling, so tag them here.
  dynamic "tag_specifications" {
    for_each = ["instance", "volume", "network-interface"]

    content {
      resource_type = tag_specifications.value
      tags          = merge(local.common_tags, { Name = "${local.name}-app" })
    }
  }

  update_default_version = true

  lifecycle {
    create_before_destroy = true
  }
}

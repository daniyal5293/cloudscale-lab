# ---------------------------------------------------------------------------
# Application Load Balancer (internet-facing, HTTP only).
# No custom domain or certificate is needed: the demo uses the ALB's AWS DNS name.
# ---------------------------------------------------------------------------

resource "aws_lb" "app" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Reject requests with malformed headers instead of forwarding them.
  drop_invalid_header_fields = true
  # Allow `terraform destroy` to remove it (important for cost cleanup).
  enable_deletion_protection = false

  tags = { Name = "${local.name}-alb" }
}

# The target group is the set of instances the ALB can route to. The Auto Scaling
# Group registers and deregisters instances here automatically.
resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  load_balancing_algorithm_type = "round_robin"

  # On scale-in, give in-flight requests 30 s to finish (default is 300 s, which
  # would make scale-in demos needlessly slow; this app's requests take milliseconds).
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/api/health"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 15 # seconds between checks
    timeout             = 5  # seconds before a check counts as failed
    healthy_threshold   = 2  # 2 passes  (~30 s) -> healthy
    unhealthy_threshold = 2  # 2 failures (~30 s) -> unhealthy
  }

  tags = { Name = "${local.name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

locals {
  # Short prefix used in resource names, e.g. "cloudscale-lab-demo-alb".
  name = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # The first N Availability Zones in the region (N = var.az_count, default 2).
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# Availability Zones that are enabled by default (excludes opt-in Local/Wavelength Zones).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# AWS-maintained public parameter that always points at the latest Amazon Linux 2023
# AMI for x86_64 (t3.* instances are x86_64). Reading it is free.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Look up the AMI itself to learn its root device name and minimum volume size.
data "aws_ami" "al2023" {
  owners = ["amazon"]

  filter {
    name   = "image-id"
    values = [data.aws_ssm_parameter.al2023_ami.insecure_value]
  }
}

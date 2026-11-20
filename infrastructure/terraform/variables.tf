# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in resource names and the Project tag."
  type        = string
  default     = "cloudscale-lab"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3-20 characters: lowercase letters, digits and hyphens (ALB/target group names are limited to 32 characters)."
  }
}

variable "environment" {
  description = "Environment label used in resource names and tags."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters/digits."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Each public subnet gets a /24 inside it."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones (and public subnets). An ALB needs at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (an Application Load Balancer requires at least two AZs)."
  }
}

variable "allowed_http_cidrs" {
  description = "IPv4 CIDRs allowed to reach the ALB on port 80. Narrow to your own IP (x.x.x.x/32) for a private demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Compute / container
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type. Must be x86_64 to match the linux/amd64 image, and launchable on your account plan."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB (gp3, encrypted)."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 30
    error_message = "root_volume_size must be between 8 and 30 GiB."
  }
}

variable "detailed_monitoring" {
  description = "Enable EC2 detailed (1-minute) monitoring. This is a PAID CloudWatch feature; scaling does not need it."
  type        = bool
  default     = false
}

variable "cpu_credits" {
  description = "T3 CPU credit mode. \"unlimited\": new instances can burst during boot/load; CPU above baseline is billed at $0.05 per vCPU-hour. \"standard\": never billed extra, but new instances start with ~0 credits and are throttled to 10% CPU (too slow to boot within the grace period)."
  type        = string
  default     = "unlimited"

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be \"standard\" or \"unlimited\"."
  }
}

variable "container_image" {
  description = "Public container image to run, e.g. ghcr.io/<github-user>/cloudscale-lab:sha-abc1234."
  type        = string

  validation {
    condition     = length(var.container_image) > 0 && !strcontains(var.container_image, "<")
    error_message = "Set container_image to your real public image (replace the <placeholder>)."
  }
}

variable "app_port" {
  description = "Port the container listens on (and the port the target group sends traffic to)."
  type        = number
  default     = 3000
}

# ---------------------------------------------------------------------------
# Auto Scaling
# ---------------------------------------------------------------------------

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 1

  validation {
    condition     = var.asg_min_size >= 1
    error_message = "asg_min_size must be at least 1 so the ALB always has a target."
  }
}

variable "asg_desired_capacity" {
  description = "Initial desired capacity. After creation, Auto Scaling owns this value (Terraform ignores drift)."
  type        = number
  default     = 1

  validation {
    condition     = var.asg_desired_capacity >= var.asg_min_size && var.asg_desired_capacity <= var.asg_max_size
    error_message = "asg_desired_capacity must be between asg_min_size and asg_max_size."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances. Hard ceiling for scale-out, and therefore for cost."
  type        = number
  default     = 3

  validation {
    condition     = var.asg_max_size >= var.asg_min_size && var.asg_max_size <= 4
    error_message = "asg_max_size must be >= asg_min_size and <= 4 (cost guardrail for this demo)."
  }
}

variable "requests_per_target_per_minute" {
  description = "Target tracking value for ALBRequestCountPerTarget (requests per instance per minute)."
  type        = number
  default     = 600

  validation {
    condition     = var.requests_per_target_per_minute >= 10
    error_message = "requests_per_target_per_minute must be at least 10."
  }
}

variable "health_check_grace_period" {
  description = "Seconds after launch before failed ELB health checks can cause Auto Scaling to replace an instance. Covers boot + Docker install + image pull (~1.5-3 min on t3.micro)."
  type        = number
  default     = 300
}

variable "instance_warmup" {
  description = "Default instance warm-up (seconds): how long a new instance is excluded from scaling metrics."
  type        = number
  default     = 120
}

variable "enable_cpu_policy" {
  description = "OPTIONAL experiment: add a second target-tracking policy on average CPU utilization. Creates 2 more CloudWatch alarms."
  type        = bool
  default     = false
}

variable "cpu_target_percent" {
  description = "Target average CPU % for the optional CPU policy."
  type        = number
  default     = 50
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

variable "alarm_email" {
  description = "Optional e-mail address for alarm notifications (SNS). Leave empty to create alarms without notifications."
  type        = string
  default     = ""
}

variable "latency_alarm_threshold_seconds" {
  description = "p95 target response time (seconds) above which the latency alarm fires."
  type        = number
  default     = 1
}

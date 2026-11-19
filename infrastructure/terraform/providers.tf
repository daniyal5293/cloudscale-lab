provider "aws" {
  region = var.aws_region

  # Applied to every taggable resource Terraform creates. The Project tag is what
  # scripts/verify-cleanup.ps1 searches for to prove nothing was left behind.
  default_tags {
    tags = local.common_tags
  }
}

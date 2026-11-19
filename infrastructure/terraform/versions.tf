terraform {
  # 1.9+ is required because variable validations below reference other variables.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State is stored locally (terraform.tfstate, git-ignored). This is a single-person
  # educational project, so a remote S3 backend would add cost and complexity for no gain.
}

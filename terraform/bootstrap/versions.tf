terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  # Local state on purpose: this is a tiny, rarely-changed, one-time
  # bootstrap module, applied by a human with their own AWS credentials
  # (never by CI, since CI doesn't exist yet when this runs). No need
  # for a remote backend here.
}

provider "aws" {
  region = var.aws_region
}

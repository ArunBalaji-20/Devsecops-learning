terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # No backend block on purpose: this defaults to local state, which is
  # fine while you're the only one applying it. Once you're ready, copy
  # backend.tf.example -> backend.tf and fill in an S3 bucket + DynamoDB
  # lock table so CI can run `terraform apply` too. See README.md.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "terraform"
      },
      var.tags
    )
  }
}

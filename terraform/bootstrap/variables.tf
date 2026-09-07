variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "devsecops-notes"
}

variable "github_org" {
  description = "Your GitHub username or org, e.g. \"arunbalaji072\"."
  type        = string
}

variable "github_repo" {
  description = "The repo name (no org prefix), e.g. \"devsecops-notes-app\"."
  type        = string
}

variable "create_oidc_provider" {
  description = "Most AWS accounts only need ONE GitHub OIDC provider total, no matter how many repos/roles use it. Set this to false (and fill in existing_oidc_provider_arn) if some other project already created one — AWS rejects a second provider for the same URL."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Only used when create_oidc_provider = false."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources."
  type        = string
  default     = "devsecops-notes"
}

variable "environment" {
  description = "Deployment environment name (dev/staging/prod)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# --- networking ---

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Subnets for the ALB and the ECS tasks. Public so Fargate tasks don't need a NAT Gateway (~$32/mo saved) — see README for the production alternative (private subnets + NAT or VPC endpoints)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Subnets for RDS only. No route to the internet — RDS doesn't need one."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# --- application / ECS ---

variable "container_port" {
  type    = number
  default = 5000
}

variable "app_image_tag" {
  description = "Tag of the app image in ECR to deploy. The CD pipeline overrides this with the git SHA it just built (see .github/workflows/cd.yml)."
  type        = string
  default     = "latest"
}

variable "fargate_cpu" {
  description = "Fargate task vCPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "fargate_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running tasks. Kept at 1 to stay cheap; bump for real availability."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  type    = number
  default = 14
}

# --- database ---

variable "db_name" {
  type    = string
  default = "notes"
}

variable "db_username" {
  type    = string
  default = "notes_app"
}

variable "db_instance_class" {
  description = "db.t3.micro is free-tier eligible for new AWS accounts."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_engine_version" {
  description = "Postgres version. AWS periodically deprecates old minor versions — if apply fails with an engine-version error, run: aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion' --output text, and update this."
  type        = string
  default     = "16.4"
}

variable "db_multi_az" {
  description = "Off by default to stay in/near the free tier. Turn on for real availability."
  type        = bool
  default     = false
}

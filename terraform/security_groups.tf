resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Internet-facing ALB. HTTP only for now (see README for adding an ACM cert + HTTPS listener)."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "To ECS tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-ecs-"
  description = "Fargate tasks. Only reachable from the ALB, never directly from the internet."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from the ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound to ECR, Secrets Manager, RDS, CloudWatch Logs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.project_name}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "Postgres. Only reachable from the ECS tasks, never from the internet."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "Unrestricted egress (RDS doesn't route out of the VPC anyway — see network.tf, private subnets have no route to the internet)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.project_name}-rds-sg" }
}

# Locks down the VPC's auto-created default security group so nothing
# can accidentally attach to it and get a permissive rule set. Nothing
# in this project uses it — everything gets its own purpose-built SG
# above.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # No ingress/egress blocks = no rules = all traffic denied.
  tags = { Name = "${var.project_name}-default-sg-locked-down" }
}

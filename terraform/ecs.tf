resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # enable for real observability; costs a bit more
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Plain, non-secret config as env vars. Nothing here is sensitive —
      # compare with `secrets` below for what actually needs protecting.
      environment = [
        { name = "FLASK_ENV", value = "production" },
        { name = "PORT", value = tostring(var.container_port) },
        { name = "DB_HOST", value = aws_db_instance.notes.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.notes.port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USER", value = var.db_username },
        # See terraform/alb.tf for why this is false until HTTPS is added.
        { name = "FORCE_HTTPS_COOKIES", value = "false" },
      ]

      # Pulled from Secrets Manager at task start by the ECS agent —
      # never baked into the image, never in a plain env var, never in
      # git. This is the pattern gitleaks/trufflehog-style secrets
      # scanning in ci.yml exists to make sure nobody accidentally
      # bypasses.
      secrets = [
        {
          name      = "FLASK_SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.flask_secret_key.arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_db_instance.notes.master_user_secret[0].secret_arn}:password::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = { Name = var.project_name }
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  # False so `terraform apply` doesn't hang/fail the very first time,
  # before any image has been pushed to ECR. The CD pipeline pushes the
  # image and applies again right after — see .github/workflows/cd.yml.
  wait_for_steady_state = false

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http, aws_iam_role_policy.ecs_execution_secrets]

  # Deliberately NOT ignoring task_definition changes: every deploy in
  # this project is a `terraform apply -var="app_image_tag=<sha>"` (see
  # cd.yml), so the service should always track whatever task
  # definition revision Terraform just created.

  tags = { Name = "${var.project_name}-service" }
}

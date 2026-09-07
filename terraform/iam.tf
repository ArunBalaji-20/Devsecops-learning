data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- execution role: what ECS itself needs to start the task (pull the
# image, write logs, fetch secrets and inject them as env vars) ---

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_secrets" {
  statement {
    sid       = "ReadAppSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.flask_secret_key.arn,
      aws_db_instance.notes.master_user_secret[0].secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "${var.project_name}-ecs-execution-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}

# --- task role: what the *application code* is allowed to do against
# AWS APIs at runtime. This app doesn't call any AWS APIs today, so it
# gets nothing — least privilege. Add statements here (scoped tightly,
# never "*") if/when the app needs, say, S3 access. ---

resource "aws_iam_role" "ecs_task" {
  name               = "${var.project_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

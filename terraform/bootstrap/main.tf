# One-time bootstrap: lets GitHub Actions authenticate to AWS via OIDC
# (short-lived, no long-lived AWS access keys stored as GitHub secrets).
# Apply this ONCE, locally, with your own AWS credentials, before the
# cd.yml workflow can run. See README.md for the full walkthrough.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC root CA thumbprint. AWS has managed/validated this
  # automatically since mid-2023, but the argument is still required by
  # the provider; this is the long-standing published value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea"]

  tags = { Name = "github-actions-oidc" }
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restricted to pushes on main only — pull_request runs and other
    # branches never get AWS credentials. Tighten further (e.g. to a
    # specific environment) once GitHub Environments are set up.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "${var.project_name}-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json

  tags = { Name = "${var.project_name}-github-actions-deploy" }
}

# Deliberately broad (this is a learning project, and Terraform needs to
# manage VPC/ECS/RDS/IAM/etc. end to end). The two genuinely dangerous
# categories — passing/creating IAM roles, and reading secrets — are
# scoped down to this project's own resources. For a real production
# setup you'd split this further (a narrower "plan" role most PRs use,
# a separate "apply" role gated by a manual approval).
data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "InfraManagement"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "rds:*",
      "logs:*",
      "application-autoscaling:*",
      "tag:GetResources",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamForEcsRolesOnly"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:aws:iam::*:role/${var.project_name}-*",
    ]
  }

  statement {
    sid    = "SecretsForThisProjectOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:TagResource",
      "secretsmanager:UpdateSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:*:*:secret:${var.project_name}/*",
      "arn:aws:secretsmanager:*:*:secret:rds!*",
    ]
  }

  statement {
    sid       = "TerraformStateIfUsingS3Backend"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = ["*"] # tighten to your state bucket's ARN once you add backend.tf
  }

  statement {
    sid       = "TerraformLockTableIfUsingS3Backend"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["*"] # tighten to your lock table's ARN once you add backend.tf
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "${var.project_name}-deploy-policy"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}

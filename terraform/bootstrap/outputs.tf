output "github_actions_role_arn" {
  description = "Put this in the GitHub repo as an Actions secret named AWS_ROLE_ARN (or reference it directly in cd.yml — see README.md)."
  value       = aws_iam_role.github_actions_deploy.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

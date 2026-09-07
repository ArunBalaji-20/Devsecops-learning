output "app_url" {
  description = "Where the app is reachable once the service is healthy."
  value       = "http://${aws_lb.app.dns_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "rds_endpoint" {
  value = aws_db_instance.notes.address
}

output "rds_master_secret_arn" {
  description = "Where the RDS-managed master password lives. Read it with: aws secretsmanager get-secret-value --secret-id <this-arn> --query SecretString --output text | jq ."
  value       = aws_db_instance.notes.master_user_secret[0].secret_arn
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app.name
}

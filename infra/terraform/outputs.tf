output "lightdash_url" {
  value = "https://lightdash.${local.domain}"
}

output "chat_url" {
  description = "Basic auth: user 'juan', password in SSM /juan/basic-auth-password"
  value       = "https://chat.${local.domain}"
}

output "dagster_url" {
  description = "Basic auth: user 'juan', password in SSM /juan/basic-auth-password"
  value       = "https://dagster.${local.domain}"
}

output "warehouse_host" {
  description = "Read-only reviewer login: juan_reader (TLS required), password in SSM /juan/postgres-reader-password"
  value       = aws_db_instance.warehouse.address
}

output "instance_id" {
  value = aws_instance.app.id
}

output "github_actions_role_arn" {
  description = "Set as the AWS_ROLE_ARN repository variable for .github/workflows/deploy.yml"
  value       = aws_iam_role.github.arn
}


output "dashboard_db_url_secret_arn" {
  value       = aws_secretsmanager_secret.dashboard_db_url.arn
  description = "ARN of the secret containing dashboard-api's DATABASE_URL"
}
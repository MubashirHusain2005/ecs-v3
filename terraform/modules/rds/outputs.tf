output "dashboard_db_url_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}


output "rds_endpoint" {
  value = aws_db_instance.PostgreSQL_rds.address
}
#output "cloudwatch_loggroup" {
  #value = aws_cloudwatch_log_group.ecs_logs
#}

output "ecs_sg" {
  value = aws_security_group.ecs.id
}
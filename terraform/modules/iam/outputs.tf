output "ecs_task_execution_role" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "vpc_flow_logs_role" {
  value = aws_iam_role.vpc_flow_logs_role.arn
}

output "ecs_task_role" {
  value = aws_iam_role.ecs_task_role.arn
}
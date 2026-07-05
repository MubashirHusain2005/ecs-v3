# ECS TASK EXECUTION ROLE

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.name_prefix}-ecstaskexecutionrole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-ecs-execution-role"
  }
}

# Attach AWS-managed execution policies
resource "aws_iam_role_policy" "ecs_task_execution" {
  name = "${var.name_prefix}-ecs-execution-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ecr:GetAuthorizationToken",
        "ecr:BatchImportUpstreamImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "servicediscovery:DiscoverInstances",
        "servicediscovery:GetService",
        "servicediscovery:GetInstancesHealthStatus",
        "ecs:DescribeServices"
      ]
      Resource = "*"
    }]
  })
}



# ECS TASK ROLE 

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-ecs-task-role"
  }
}


resource "aws_iam_role_policy" "ecs_task_policies" {
  name = "${var.name_prefix}-ecs-task-logs-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:BatchGetSecretValue",
        "secretsmanager:ListSecrets"
      ]
      Resource = "*"
    }]
  })
}



resource "aws_iam_role_policy_attachment" "ecs_task_role_policyattachment" {
  role       = aws_iam_role.ecs_task_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}
# ECS TASK EXECUTION ROLE

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecstask-executionrole"

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
    Name = "ecs-execution-role"
  }
}

# Attach AWS-managed execution policies
resource "aws_iam_role_policy" "ecs_task_execution" {
  name = "ecs-execution-policy"
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
        "ecs:DescribeServices",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:BatchGetSecretValue",
        "secretsmanager:ListSecrets"
        #"aws:SourceVpc",
        #"aws:SourceVpce"
      ]
      Resource = "*"
    }]
  })
}

# ECS TASK ROLE 

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

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
    Name = "ecs-task-role"
  }
}


resource "aws_iam_role_policy" "ecs_task_policies" {
  name = "ecs-task-logs-policy"
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
        "secretsmanager:ListSecrets",
        "sqs:SendMessage",
        "sqs:RecieveMessage",
        "sqs:DeleteMessage",
      ]
      Resource = "*"
    }]
  })
}


resource "aws_iam_role_policy_attachment" "ecs_task_role_policyattachment" {
  role       = aws_iam_role.ecs_task_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}


###Roles for CloudWatch

resource "aws_iam_role" "vpc_flow_logs_role" {
  name = "vpc-flow-logs-cloudwatch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name    = "vpc-flow-logs-cloudwatch-role"
    Purpose = "vpc-flow-logs"
  }
}

resource "aws_iam_policy" "vpc_flow_logs_policy" {
  name = "vpc-flow-logs-cloudwatch-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:DeleteLogGroup"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "vpc-flow-logs-cloudwatch-policy"
    Purpose = "vpc-flow-logs"
  }
}

#IAM policy attachement for CloudWatch
resource "aws_iam_role_policy_attachment" "vpc_flow_logs_attach" {
  role       = aws_iam_role.vpc_flow_logs_role.name
  policy_arn = aws_iam_policy.vpc_flow_logs_policy.arn
}

###IAM role for Observability

resource "aws_iam_role" "monitoring_role" {
  name = "monitoringRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# iam policy for prometheus to pull metrics from cloud watch 
resource "aws_iam_role_policy_attachment" "cw_read" {
  role       = aws_iam_role.monitoring_role.id
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccessV2"
}

resource "aws_iam_role_policy_attachment" "ecs_full_access" {
  role = aws_iam_role.monitoring_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}


#resource "aws_iam_policy" "yace_policy" {
 # name = "yace-cloudwatch-policy"

  #policy = jsonencode({
   # Version = "2012-10-17"
   # Statement = [
   #   {
    #    Effect = "Allow"
     #   Action = [
      #    "cloudwatch:GetMetricData",
       #   "cloudwatch:ListMetrics"
    #    ]
    #    Resource = "*"
   #   },
    #  {
    #    Effect = "Allow"
     #   Action = [
      #    "ecs:ListClusters",
       #   "ecs:ListServices",
        #  "ecs:DescribeServices"
     #   ]
     #   Resource = "*"
    #  },
    #  {
     #   Effect = "Allow"
      #  Action = [
      #    "elasticloadbalancing:DescribeLoadBalancers",
      #    "elasticloadbalancing:DescribeTargetGroups",
       #   "elasticloadbalancing:DescribeTags"
     #   ]
     #   Resource = "*"
    #  },
    #  {
     #   Effect = "Allow"
     #   Action = [
      #    "tag:GetResources"
     #   ]
     #   Resource = "*"
    #  },
    #  {
     #   Effect = "Allow"
     #   Action = [
     #     "iam:ListAccountAliases"
      #  ]
     #   Resource = "*"
    #  }
   # ]
 # })
#}

#resource "aws_iam_role_policy_attachment" "yace_attach" {
 # role       = aws_iam_role.monitoring_role.name
 # policy_arn = aws_iam_policy.yace_policy.arn
#}

resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "monitoring-instance-profile"
  role = aws_iam_role.monitoring_role.name
}


# Enables SSM Session Manager access (no SSH key, no bastion, no public IP needed)
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}



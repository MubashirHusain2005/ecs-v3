provider "aws" {
  region = "eu-west-2"
}

##S3 Bucket to store tf state file

resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = "terraformstatebucket20018"

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "s3 bucket"
    Description = "s3 for tf backend"
  }
}

##Enabled Versioning

resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

## Enable encryption 

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

##Block All public access- state files should never be public

resource "aws_s3_bucket_public_access_block" "terraform_s3_access" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##Bucket policy enforces TLS connections only 
resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "${aws_s3_bucket.terraform_state_bucket.arn}"
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.terraform_state_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          #aws_s3_bucket.terraform_state_bucket.arn,
          "${aws_s3_bucket.terraform_state_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

#OIDC for github actions

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}


resource "aws_iam_role" "github_oidc_role" {
  name = "githubactions-oidc"
  lifecycle {
    prevent_destroy = false
  }
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          Federated = aws_iam_openid_connect_provider.oidc.arn
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:MubashirHusain2005/ecs-v3:*"
          }
        }
      },
    ]
  })
}

locals {
  oidc_role_name = aws_iam_role.github_oidc_role.name
}

# ---------------------------------------------------------------------------
# 1. State backend + KMS + logging
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "oidc_state_and_kms" {
  name        = "oidc-state-and-kms"
  path        = "/"
  description = "S3 state backend, DynamoDB lock table, KMS, CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = ["*"]
      },
      {
        Sid    = "ReadWriteStateObject"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state_bucket.arn}/*"
      },
      {
        Sid    = "StateLockTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/terraform-lock"
      },
      {
        Sid    = "AccessToKMS"
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:DescribeKey",
          "kms:EnableKey",
          "kms:PutKeyPolicy",
          "kms:TagResource",
          "kms:CreateAlias",
          "kms:ScheduleKeyDeletion",
          "kms:EnableKeyRotation",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:ListResourceTags",
          "kms:ListAliases",
          "kms:DeleteAlias",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:CreateGrant"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:ListTagsForResource",
          "logs:TagResource",
          "logs:DeleteLogGroup",
          "logs:DeleteRetentionPolicy"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_openid_connect_provider.oidc]
}

# ---------------------------------------------------------------------------
# 2. IAM management + ECS
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "oidc_iam_and_ecs" {
  name        = "oidc-iam-and-ecs"
  path        = "/"
  description = "IAM role/policy management, PassRole to ECS, ECS cluster/service/task management"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:GetUserPolicy",
          "iam:ListGroupsForUser",
          "iam:ListAttachedUserPolicies",
          "iam:ListUserPolicies",
          "iam:GetUser",
          "iam:GetGroupPolicy",
          "iam:GetPolicyVersion",
          "iam:GetPolicy",
          "iam:ListAttachedGroupPolicies",
          "iam:ListGroupPolicies",
          "iam:ListPolicyVersions",
          "iam:ListPolicies",
          "iam:ListUsers",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:GetInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMManageRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        ]
      },
      {
        Sid      = "PassRolesToECS"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ECS"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:DeleteCluster",
          "ecs:DescribeClusters",
          "ecs:ListClusters",
          "ecs:CreateService",
          "ecs:UpdateService",
          "ecs:DeleteService",
          "ecs:DescribeServices",
          "ecs:ListServices",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:ListContainerInstances",
          "ecs:DescribeContainerInstances",
          "ecs:StartTask",
          "ecs:StopTask",
          "ecs:RunTask",
          "ecs:TagResource",
          "ecs:UntagResource",
          "ecs:PutClusterCapacityProviders",
          "ecs:CreateCapacityProvider",
          "ecs:DeleteCapacityProvider",
          "ecs:DescribeCapacityProviders"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_openid_connect_provider.oidc]
}

# ---------------------------------------------------------------------------
# 3. Networking (VPC, subnets, routing, ELB)
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "oidc_networking" {
  name        = "oidc-networking"
  path        = "/"
  description = "VPC, subnets, security groups, routing, load balancing"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Networking"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
          "ec2:DescribeVpcs", "ec2:DescribeVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:DescribeSubnets",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
          "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:DescribeRouteTables",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:DescribeInternetGateways",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
          "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses",
          "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs", "ec2:DescribeFlowLogs",
          "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeImages",
          "ec2:ImportKeyPair",
          "ec2:CreateVpcEndpoint"
        ]
        Resource = "*"
      },

      {
        Sid = "Route53"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetHostedZone",
          "route53:CreateHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:ListTagsForResource",
          "acm:RequestCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "ElasticLoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeTargetGroupAttributes"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_openid_connect_provider.oidc]
}

# ---------------------------------------------------------------------------
# 4. Data services (ElastiCache, CloudMap, DynamoDB, RDS, SQS, Secrets, ECR)
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "oidc_data_services" {
  name        = "oidc-data-services"
  path        = "/"
  description = "ElastiCache, ServiceDiscovery, DynamoDB, RDS, SQS, SecretsManager, ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ElastiCache"
        Effect = "Allow"
        Action = [
          "elasticache:CreateServerlessCache",
          "elasticache:DeleteServerlessCache",
          "elasticache:DescribeServerlessCaches",
          "elasticache:ModifyServerlessCache",
          "elasticache:CreateCacheSubnetGroup",
          "elasticache:DeleteCacheSubnetGroup",
          "elasticache:DescribeCacheSubnetGroups",
          "elasticache:TagResource",
          "elasticache:ListTagsForResource",
          "elasticache:CreateCacheCluster"
        ]
        Resource = "*"
      },
      {
        Sid    = "ServiceDiscovery"
        Effect = "Allow"
        Action = [
          "servicediscovery:CreateHttpNamespace",
          "servicediscovery:CreatePrivateDnsNamespace",
          "servicediscovery:DeleteNamespace",
          "servicediscovery:GetNamespace",
          "servicediscovery:ListNamespaces",
          "servicediscovery:GetOperation",
          "servicediscovery:CreateService",
          "servicediscovery:DeleteService",
          "servicediscovery:GetService",
          "servicediscovery:ListServices",
          "servicediscovery:UpdateService",
          "servicediscovery:TagResource",
          "servicediscovery:DiscoverInstances",
          "servicediscovery:GetInstancesHealthStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:ListTagsOfResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:ModifyDBInstance",
          "rds:DescribeDBInstances",
          "rds:CreateDBCluster",
          "rds:DeleteDBCluster",
          "rds:ModifyDBCluster",
          "rds:DescribeDBClusters",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:DescribeDBSubnetGroups",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "SQS"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:TagQueue",
          "sqs:ListQueues",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:SendMessage",
          "sqs:listqueuetags"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:TagResource",
          "secretsmanager:GetResourcePolicy" 
        ]
        Resource = "*"
      },
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:DescribeRepositories",
          "ecr:SetRepositoryPolicy",
          "ecr:TagResource"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_openid_connect_provider.oidc]
}

# ---------------------------------------------------------------------------
# Attachments — all four attach to the same OIDC role
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "oidc_state_and_kms" {
  role       = local.oidc_role_name
  policy_arn = aws_iam_policy.oidc_state_and_kms.arn
}

resource "aws_iam_role_policy_attachment" "oidc_iam_and_ecs" {
  role       = local.oidc_role_name
  policy_arn = aws_iam_policy.oidc_iam_and_ecs.arn
}

resource "aws_iam_role_policy_attachment" "oidc_networking" {
  role       = local.oidc_role_name
  policy_arn = aws_iam_policy.oidc_networking.arn
}

resource "aws_iam_role_policy_attachment" "oidc_data_services" {
  role       = local.oidc_role_name
  policy_arn = aws_iam_policy.oidc_data_services.arn
}

data "aws_caller_identity" "current" {}

#resource "aws_iam_role_policy_attachment" "oidc_s3_access" {
 # role       = local.oidc_role_name
 # policy_arn = aws_iam_policy.oidc_access_aws.arn
#}


##KMS Encryption of ECR Repos


resource "aws_kms_key" "kms_key" {
  description             = "Encryption KMS key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
}



resource "aws_kms_alias" "kms_alias" {
  name          = "alias/kms-ecr"
  target_key_id = aws_kms_key.kms_key.id

}


resource "aws_kms_key_policy" "kms_key_policy" {
  key_id = aws_kms_key.kms_key.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      },


    ]
  })
}


#IAM Role for ECR

resource "aws_iam_role" "ecr_role" {
  name = "ecr"
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
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_policy" "ecr_policy" {
  name = "ecr-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_policy" {
  policy_arn = aws_iam_policy.ecr_policy.arn
  role       = aws_iam_role.ecr_role.id
}



# ECR to store my api-gateway Docker image
resource "aws_ecr_repository" "api_gateway" {
  name                 = "api-gateway"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }
  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "api_gateway_lifecycle" {
  repository = aws_ecr_repository.api_gateway.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "dashboard_api" {
  name                 = "dashboard-api"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "dashboard_lifecycle" {
  repository = aws_ecr_repository.dashboard_api.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "inventory_service" {
  name                 = "inventory-service"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "inventory_lifecycle" {
  repository = aws_ecr_repository.inventory_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "notification_service" {
  name                 = "notification-service"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "notification_lifecycle" {
  repository = aws_ecr_repository.notification_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "order_service" {
  name                 = "order-service"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "order_service_lifecycle" {
  repository = aws_ecr_repository.order_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}


# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "payment_service" {
  name                 = "payment-service"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "payment_service_lifecycle" {
  repository = aws_ecr_repository.payment_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "scheduler_service" {
  name                 = "scheduler"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "scheduler_service_lifecycle" {
  repository = aws_ecr_repository.payment_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "shipping_service" {
  name                 = "shipping-service"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "shipping_service_lifecycle" {
  repository = aws_ecr_repository.shipping_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR to store my dashboard-api Docker image
resource "aws_ecr_repository" "worker_service" {
  name                 = "worker"
  image_tag_mutability = "MUTABLE"

  # Scan images for vulnerabilities on push
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encryption at rest
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key.arn
  }

}

##ECR lifecycle policy to clean up old images to save on storage costs

resource "aws_ecr_lifecycle_policy" "worker_service_lifecycle" {
  repository = aws_ecr_repository.worker_service.id

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 12 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 12
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
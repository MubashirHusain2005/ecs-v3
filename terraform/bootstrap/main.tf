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

resource "aws_iam_policy" "oidc_access_aws" {
  name        = "oidc_access_aws"
  path        = "/"
  description = "Policy document to allow OIDC access to AWS resources during CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "${aws_s3_bucket.terraform_state_bucket.arn}"
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
          "logs:DeleteLogGroup",
          "logs:DeleteRetentionPolicy"
        ]
        Resource = "*"
      },

      {
        Sid    = "IAM"
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
          "iam:ListUsers"
        ],
        Resource = "*"
      },

      {
        Sid = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ],
        Resource = "*"
      },

      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:DeleteSecret"
        ]
        Resource = "*"
      },

      {
        Sid    = "ECS"
        Effect = "Allow"
        Action = [
          "ecs:ListContainerInstances",
          "ecs:RegisterContainerInstance",
          "ecs:SubmitContainerInstance",
          "ecs:SubmitTaskStateChange",
          "ecs:DescribeContainerInstances",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:CreateCluster",
          "ecs:DescribeCluster",
          "ecs:DeleteCluster",
          "ecs:ListClusters",
          "ecs:Describe*",
          "ecs:List*",
          "ecs:UpdateContainerAgent",
          "ecs:StartTask",
          "ecs:StopTask",
          "ecs:RunTask"
        ]
        Resource = "*"
      },


      {
        Sid    = "ElasticLoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DeleteLoadBalancer"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_openid_connect_provider.oidc]
}

resource "aws_iam_role_policy_attachment" "oidc_s3_access" {
  role       = aws_iam_role.github_oidc_role.name
  policy_arn = aws_iam_policy.oidc_access_aws.arn
}


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
          AWS = "arn:aws:iam::038774803581:user/aws-user"
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
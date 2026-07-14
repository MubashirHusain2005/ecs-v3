data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_kms_key" "kms_key" {
  key_id = "alias/kms-ecr"
}

resource "aws_vpc" "ecs_vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = var.inst_tenancy
  enable_dns_hostnames = var.enable_host
  enable_dns_support   = var.enable_support

  tags = {
    Name = "Main-VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ecs_vpc.id

  tags = {
    Name = "IGW"
  }
}

resource "aws_subnet" "public" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = each.key
  }

  depends_on = [aws_vpc.ecs_vpc]

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags]
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }

  depends_on = [aws_vpc.ecs_vpc, aws_internet_gateway.igw]
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_subnet" "private" {
  for_each                = var.private_subnets
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = each.key
  }

  depends_on = [aws_vpc.ecs_vpc]

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [tags]
  }
}

# No NAT gateway, no EIPs — private subnets have no internet route.
# Route table exists only so the S3 Gateway endpoint has something to attach to,
# and so each private subnet is explicitly associated rather than using the VPC's
# implicit main route table.
resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.ecs_vpc.id

  tags = {
    Name = "rt-private-${each.key}"
  }

  depends_on = [aws_vpc.ecs_vpc]
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

### CloudWatch for VPC logs

resource "aws_flow_log" "cloud_watch" {
  iam_role_arn    = var.vpc_flow_logs_role
  log_destination = aws_cloudwatch_log_group.cloud_watch_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.ecs_vpc.id
}

resource "aws_cloudwatch_log_group" "cloud_watch_logs" {
  name              = "logs_for_cloudwatch"
  retention_in_days = 7
  #kms_key_id        = data.aws_kms_key.kms_key.arn
}

### VPC Endpoints- private-subnet ECS tasks reach any AWS service.

resource "aws_security_group" "vpc_endpoints_sg" {
  name   = "vpce-sg"
  vpc_id = aws_vpc.ecs_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # should be restricted to inside the VPC only in prod
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vpce-sg"
  }
}

# S3 — required for ECR image layer downloads (Gateway type, free, attaches via route table)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.ecs_vpc.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [for rt in aws_route_table.private : rt.id]

  tags = {
    Name = "s3-gateway-endpoint"
  }
}

# ECR API — auth and metadata calls
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.ecs_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "ecr-api-endpoint"
  }
}

# ECR Docker — image manifest/layer pull requests
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.ecs_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "ecr-dkr-endpoint"
  }
}

# CloudWatch Logs — required for awslogs driver without NAT
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.ecs_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "logs-endpoint"
  }
}

# SQS — private queue access for your dead-letter queue / async workflows
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.ecs_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "sqs-endpoint"
  }
}

# Secrets Manager — read-only policy restricting to Get/Describe/List only
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = aws_vpc.ecs_vpc.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowReadOnly"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "secrets-manager-endpoint"
  }
}
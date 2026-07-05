##No Nat-gateways

terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.2.0"
    }
  }
}

data "aws_caller_identity" "current" {}


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


resource "aws_eip" "ngw_eip" {
  for_each = var.public_subnets

  domain = "vpc"

  tags = {
    Name = "nat-eip-${each.value.az}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "ngw" {
  for_each = var.public_subnets

  subnet_id     = aws_subnet.public[each.key].id
  allocation_id = aws_eip.ngw_eip[each.key].id

  tags = {
    Name = "nat-${each.value.az}"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw[[
      for key, subnet in var.public_subnets :
      key if subnet.az == each.value.az
    ][0]].id
  }

  tags = {
    Name = "rt-private-${each.key}"
  }

  depends_on = [aws_nat_gateway.ngw]
}


resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}


###CloudWatch for VPC logs

resource "aws_flow_log" "cloud_watch" {
  iam_role_arn    = var.vpc_flow_logs_role
  log_destination = aws_cloudwatch_log_group.cloud_watch_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.ecs_vpc.id
}

#Stores the log streams     ###not completed need to bring data block
resource "aws_cloudwatch_log_group" "cloud_watch_logs" {
  name              = "logs_for_cloudwatch"
  retention_in_days = 7
  kms_key_id        = data.aws_kms_key.kms_key.arn
}

#####Security Groups
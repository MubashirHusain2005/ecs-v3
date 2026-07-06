resource "aws_elasticache_serverless_cache" "serverless_cache" {
  engine = "valkey"
  name   = "example"

  cache_usage_limits {
    data_storage {
      maximum = 10
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }

  daily_snapshot_time      = "09:00"
  description              = "ElastiCache Valkey serverless cache"
  major_engine_version     = "7"
  snapshot_retention_limit = 7

  security_group_ids = [aws_security_group.elasticache_sg.id]
  subnet_ids         = var.private_subnet_ids

}

resource "aws_security_group" "elasticache_sg" {
  name        = "elasticache-sg"
  description = "ElastiCache Valkey - allow access from app tier only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    #security_groups = [var.app_security_group_id]
    description     = "Valkey access from app tier"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "elasticache-sg"
  }
}
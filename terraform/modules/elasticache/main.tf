resource "aws_elasticache_subnet_group" "redis" {
  name       = "ecs-v3-redis-subnet-groups"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "ecs-v3-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"  
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379 
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.elasticache_sg.id]
}



resource "aws_security_group" "elasticache_sg" {
  name        = "elasticache-sg"
  description = "ElastiCache  - allow access from app tier only"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 6379
    to_port   = 6379
    protocol  = "tcp"
    security_groups = [var.ecs_sg]
    description = " access from app tier"
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
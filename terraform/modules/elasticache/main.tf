resource "aws_cloudwatch_log_group" "elasticache_logs" {
  name              = "elasticache_logs"
  retention_in_days = 7

  tags = {
    Name = "elasticache-logs"
  }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "elasticache-subnet-group"
  subnet_ids = var.private_subnet_ids
}


resource "aws_elasticache_cluster" "redis" {
  cluster_id        = "mycluster"
  engine            = "redis"
  node_type         = "cache.t3.micro"
  num_cache_nodes   = 1
  port              = 6379
  apply_immediately = true
  ip_discovery      = "ipv4"
  network_type      = "ipv4"
  subnet_group_name = aws_elasticache_subnet_group.this.name
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.elasticache_logs.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }
}

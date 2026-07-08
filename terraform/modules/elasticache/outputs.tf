output "redis_endpoint" {
  value = aws_elasticache_serverless_cache.serverless_cache.endpoint[0].address
}
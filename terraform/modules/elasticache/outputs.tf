output "redis_url" {
  description = "Connection URL for the Redis cache"
  value       = "redis://${aws_elasticache_cluster.test.cache_nodes[0].address}:${aws_elasticache_cluster.test.port}"
}
#{ name = "REDIS_URL", value = "redis://${var.elasticache_address}:6379/0" },
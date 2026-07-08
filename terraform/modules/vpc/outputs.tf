output "vpc_id" {
  value = aws_vpc.ecs_vpc.id
}


output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}


output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
}


output "vpce_sg" {
  value = aws_security_group.vpc_endpoints_sg.id
}


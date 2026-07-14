variable "private_subnet_ids" {
  type = list(any)
}

variable "vpc_id" {
  type = string
}

variable "ecs_sg" {
  type = string
}
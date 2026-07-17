variable "private_subnet_ids" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "ecs_sg" {
  type = string
}

variable "environment" {
  type = string
}

variable "skip_final_snapshot" {
  type = bool
}

variable "multi_az" {
  type = bool
}

variable "instance_class" {
  type = string
}


#"db.t4g.large"
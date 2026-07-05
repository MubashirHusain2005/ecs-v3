variable "name_prefix" {
  type = string
}


variable "fargate_cpu" {
  type    = number
  default = 256
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "family" {
  type    = string
  default = "my-ecs-task"
}

variable "memory" {
  type    = string
  default = "512"
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

variable "alb_target_grp_arn" {
  type = string
}


variable "execution_role_arn" {
  type = string
}

variable "ecs_sg" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "network_mode" {
  type    = string
  default = "awsvpc"
}

variable "launch_type" {
  type    = string
  default = "FARGATE"

}

variable "desired_count" {
  type    = number
  default = 2
}

variable "retention_in_days" {
  type    = number
  default = 7
}

variable "api_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/api_gateway:v1"
}

variable "protocol" {
  type    = string
  default = "tcp"
}

variable "api_task_name" {
  type    = string
  default = "api_gateway"
}

variable "dashboard_api_task_name" {
  type    = string
  default = "dashboard-api"
}

variable "private_subnet_ids" {
  type = list(any)
}

variable "task_role_arn" {
  type = string
}

variable "dashboard-api_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/dashboard_api:v1"
}

variable "vpc_id" {
  type = string
}

variable "domain_name" {
  type = string
  default = 
}

variable "environment" {
  type = string
  default = "prod"
}

variable "dashboard_db_url_secret_arn" {
  type = string
}


variable "main_queue_url" {
  type = string
}

variable "redis_url" {
  type = string
}
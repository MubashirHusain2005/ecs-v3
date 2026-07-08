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
  default = 1 ##1 is enough for dev
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

variable "environment" {
  type    = string
  default = "prod"
}

variable "ecs_task_execution_role" {
  type = string
}

variable "ecs_task_role" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}


variable "private_subnet_ids" {
  type = list(any)
}


variable "dashboard-api_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/dashboard_api:v1"
}

variable "inventory_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/inventory_service:v1"
}

variable "notification_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/notification_service:v1"
}

variable "order_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/order_service:v1"
}

variable "payment_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/payment_service:v1"
}

variable "scheduler_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/scheduler_service:v1"
}

variable "shipping_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/shipping_service:v1"
}

variable "worker_image" {
  type    = string
  default = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/worker_service:v1"
}


variable "vpc_id" {
  type = string
}


variable "dashboard_db_url_secret_arn" {
  type = string
}


variable "main_queue_url" {
  type = string
}

variable "redis_endpoint" {
  type = string
}

variable "alb_sg" {
  type = string
}

variable "dashboard_api_tg" {
  type = string
}

variable "api_gateway_tg" {
  type = string
}

variable "vpce_sg" {
  type = string
}


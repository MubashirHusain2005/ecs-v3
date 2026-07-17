variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "acm_certificate_arn" {
  type = string
}

variable "ecs_sg" {
  type = string
}

variable "ssl_policy" {
  type    = string
  default = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "environment" {
  type = string
}

variable "enable_deletion_protection" {
  type = bool
}
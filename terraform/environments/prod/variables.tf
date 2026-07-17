variable "vpc_cidr" {
  type = string
}

variable "environment" {
  type = string
}

variable "retention_in_days" {
  type = string
}

variable "enable_deletion_protection" {
  type = bool
}

variable "sqs_message_retention_seconds" {
  type = number
}

variable "sqs_max_receive_count" {
  type = number
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
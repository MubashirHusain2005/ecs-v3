variable "environment" {
  type = string
}

variable "sqs_message_retention_seconds" {
  type = number
}

variable "sqs_max_receive_count" {
  type = number
}
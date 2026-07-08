variable "type_record" {
  description = "Type of record used for domain mapping "
  default     = "A"
}

variable "domain_name" {
  type    = string
  default = "mubashir.site"
}


variable "alb_dns_name" {
  type = string
}

variable "alb_zone" {
  type = string
}

variable "record_type" {
  type    = string
  default = "A"
}

variable "health" {
  type    = bool
  default = true
}

variable "valid_method" {
  type    = string
  default = "DNS"
}


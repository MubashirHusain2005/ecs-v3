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

variable "alb_zone_id" {
  type = string
}

variable "domain_validation_options" {

  type = list(object({

    domain_name = string

    resource_record_name = string

    resource_record_value = string

    resource_record_type = string

  }))

  default = []

}

variable "certificate_arn" {
  type = string
}


variable "record_type" {
  type    = string
  default = "A"
}

variable "health" {
  type    = string
  default = "true"
}
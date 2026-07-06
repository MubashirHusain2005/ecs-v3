data "aws_route53_zone" "primary" {
  name = var.domain_name

}

# A record so I can map www.mubashir.site onto the ALB DNS
resource "aws_route53_record" "MS" {
  zone_id = data.aws_route53_zone.primary.id
  name    = "www.${var.domain_name}"
  type    = var.record_type


  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = var.health
  }
}


resource "aws_route53_record" "apex" {
  zone_id = data.aws_route53_zone.primary.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = var.health
  }
}


#  ACM Certificate for (DNS Validation)-Requesting a certificate

resource "aws_acm_certificate" "app_cert" {
  domain_name               = var.domain_name
  validation_method         = var.valid_method
  subject_alternative_names = ["www.${var.domain_name}"]

  tags = {
    Name = "app-cert"
  }
}

# Create the DNS Validation Records

resource "aws_route53_record" "cert_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.app_cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}


# Validate ACM Certificate

resource "aws_acm_certificate_validation" "validation" {
  certificate_arn = aws_acm_certificate.app_cert.arn

  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation_record : record.fqdn
  ]

  timeouts {
    create = "5m"
  }
}
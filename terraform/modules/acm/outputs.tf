output "acm_certificate_arn" {
  value = aws_acm_certificate.app_cert.arn
}

output "domain_validation_options" {
  value = aws_acm_certificate.app_cert.domain_validation_options
}
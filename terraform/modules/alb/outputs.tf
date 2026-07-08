output "alb" {
  value = aws_lb.alb.arn
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "dashboard_api_tg" {
  value = aws_lb_target_group.dashboard_api.arn
}

output "api_gateway_tg" {
  value = aws_lb_target_group.api_gateway.arn
}


output "aws_lb_listener_http_id" {
  value = aws_lb_listener.http.id
}

output "aws_lb_listener_http_arn" {
  value = aws_lb_listener.http.arn
}


output "alb_listener_https_arn" {
  description = "The ARN of the HTTPS ALB listener"
  value       = aws_lb_listener.https.arn
}

output "alb_listener_https_id" {
  description = "The ID of the HTTPS ALB listener"
  value       = aws_lb_listener.https.id
}

output "alb_zone" {
  value = aws_lb.alb.zone_id
}

output "alb_sg" {
  value = aws_security_group.alb_sg.id
}
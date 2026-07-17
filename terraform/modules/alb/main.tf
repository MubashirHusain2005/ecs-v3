resource "aws_lb" "alb" {
  name                       = "alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = false

  tags = {
    Name = "${var.environment}-alb"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }

  }
}


resource "aws_lb_target_group" "api_gateway" {
  name        = "api-gateway-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"


  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.environment}-api-gateway-tg"
  }
}

resource "aws_lb_listener_rule" "api_gateway" {
  listener_arn = aws_lb_listener.https.arn # 
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_gateway.arn
  }

  condition {
    path_pattern {
      values = ["/api*", "/auth/*", "/healthz"]
    }
  }
}

resource "aws_lb_target_group" "dashboard_api" {
  name        = "OrdersRus"
  port        = 8086
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"


  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/dashboard/healthz"
    interval            = 30
    matcher             = "200"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.environment}-dashboard-api-tg"
  }
}

resource "aws_lb_listener_rule" "dashboard_api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 90

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard_api.arn
  }

  condition {
    path_pattern {
      values = ["/", "/dashboard", "/dashboard/*", "/healthz"]
    }
  }
}


# Application Load Balancer Security group 

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP and HTTPS inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


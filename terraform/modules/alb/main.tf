resource "aws_lb" "alb" {
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = var.alb_type
  security_groups            = [var.alb_sg]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = false

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}


resource "aws_lb_target_group" "threatcomposer_tg" {
  name        = "ThreatComposer"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"


  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/"
    matcher             = var.matcher
    interval            = var.interval
    timeout             = var.timeout
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "ThreatComposer-TG"
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.threatcomposer_tg.arn
  }
}


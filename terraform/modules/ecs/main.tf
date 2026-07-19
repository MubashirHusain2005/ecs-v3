data "aws_secretsmanager_secret" "api_gateway_secret" {
  name = "JWT_SECRET"
}


##ECS Cluster
resource "aws_ecs_cluster" "ecsv3_cluster" {
  name = "ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}


###Security Group

#Traffic to ECS Containers must come from ALB on port 8080

resource "aws_security_group" "ecs" {
  name        = "ecs-sg"
  description = "security group for the ecs services"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow traffic from ALB on 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = var.protocol
    security_groups = [var.alb_sg]
  }

  ingress {
    from_port       = 9000
    to_port         = 9001
    protocol        = "tcp"
    self            = true
    security_groups = [var.alb_sg]
  }

  ingress {
    from_port       = 8086
    to_port         = 8086
    protocol        = "tcp"
    self            = true
    security_groups = [var.alb_sg]
  }

  ingress {
    from_port       = 8080
    to_port         = 8091
    protocol        = "tcp"
    security_groups = [var.monitoring_sg]
  }

  ingress {
    from_port = 8081
    to_port   = 8086
    protocol  = "tcp"
    self      = true
  }


  ingress {
    from_port = 9090
    to_port   = 9090
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 3000
    to_port   = 3000
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/ecs/api-gateway"
  retention_in_days = 7

  tags = {
    Name = "api-gateway-logs"
  }
}

###CloudMap Namespace

resource "aws_service_discovery_private_dns_namespace" "private" {
  name        = "services.internal"
  description = "Private dns namespace for service discovery"
  vpc         = var.vpc_id
}


resource "aws_service_discovery_service" "api_gateway" {
  name = "api-gateway"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Api-gateway Task
resource "aws_ecs_task_definition" "api_gateway_task" {

  depends_on               = [aws_cloudwatch_log_group.api_gateway]
  family                   = "api-gateway"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {

      health_check = {
        command = ["CMD-SHELL", "curl -f http://localhost:8080/healthz || exit 1"]
        interval = 5
        timeout  = 5
      }

      name      = var.api_task_name
      image     = var.api_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
          hostPort      = 8080
        }
      ]

      secrets = [
        {
          name      = "JWT_SECRET"
          valueFrom = data.aws_secretsmanager_secret.api_gateway_secret.arn
        }
      ]

      environment = [

        { name = "REDIS_URL", value = "redis://${var.redis_endpoint}:6379/0" },
        { name = "ORDER_SERVICE_URL", value = "http://order-service.${aws_service_discovery_private_dns_namespace.private.name}:8081" },
        { name = "INVENTORY_SERVICE_URL", value = "http://inventory-service.${aws_service_discovery_private_dns_namespace.private.name}:8082" },
        { name = "PAYMENT_SERVICE_URL", value = "http://payment-service.${aws_service_discovery_private_dns_namespace.private.name}:8083" },
        { name = "NOTIFICATION_SERVICE_URL", value = "http://notification-service.${aws_service_discovery_private_dns_namespace.private.name}:8084" },
        { name = "SHIPPING_SERVICE_URL", value = "http://shipping-service.${aws_service_discovery_private_dns_namespace.private.name}:8085" },
        { name = "DASHBOARD_SERVICE_URL", value = "http://dashboard-api.${aws_service_discovery_private_dns_namespace.private.name}:8086" },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/api-gateway"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Api-gateway service
resource "aws_ecs_service" "api_gateway_service" {
  name             = "api-gateway"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.api_gateway_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.api_gateway_tg
    container_name   = var.api_task_name
    container_port   = var.api_gateway_container_port
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.api_gateway.arn
    container_name = "api-gateway"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}


#######
resource "aws_cloudwatch_log_group" "dashboard_api" {
  name              = "/ecs/dashboard-api"
  retention_in_days = 7

  tags = {
    Name = "api-gateway-logs"
  }
}

##CloudMap Namespace Service

resource "aws_service_discovery_service" "dashboard_api" {
  name = "dashboard-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

}

##dashboard-api Task
resource "aws_ecs_task_definition" "dashboard_api_task" {

  depends_on               = [aws_cloudwatch_log_group.dashboard_api]
  family                   = "dashboard-api"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.dashboard_api_task_name
      image     = var.dashboard-api_image
      essential = true

      portMappings = [
        {
          containerPort = 8086
          protocol      = "tcp"
          hostPort      = 8086
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/dashboard-api"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##dashboard service
resource "aws_ecs_service" "dashboard_api_service" {
  name             = "dashboard-api-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.dashboard_api_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.dashboard_api_tg
    container_name   = var.dashboard_api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.dashboard_api.arn
    container_name = "dashboard-api"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.dashboard_api_task

  ]
}


##############################################

resource "aws_cloudwatch_log_group" "inventory" {
  name              = "/ecs/inventory"
  retention_in_days = 7

  tags = {
    Name = "inventory-logs"
  }
}

##CloudMap Namespace Service Inventory

resource "aws_service_discovery_service" "inventory_service" {
  name = "inventory-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }


}

##Inventory Task
resource "aws_ecs_task_definition" "inventory_task" {

  depends_on               = [aws_cloudwatch_log_group.inventory]
  family                   = "inventory"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "inventory-service"
      image     = var.inventory_image
      essential = true

      portMappings = [
        {
          containerPort = 8082
          protocol      = "tcp"
          hostPort      = 8082
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/inventory"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Inventory service
resource "aws_ecs_service" "inventory_service" {
  name             = "inventory-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.inventory_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.inventory_service.arn
    container_name = "inventory-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.inventory_task

  ]
}


###########Notification Service

resource "aws_cloudwatch_log_group" "notification" {
  name              = "/ecs/notification"
  retention_in_days = 7

  tags = {
    Name = "notification-logs"
  }
}



resource "aws_service_discovery_service" "notification_service" {
  name = "notification-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Notification Task
resource "aws_ecs_task_definition" "notification_task" {

  depends_on               = [aws_cloudwatch_log_group.notification]
  family                   = "notification"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "notification-service"
      image     = var.notification_image
      essential = true

      portMappings = [
        {
          containerPort = 8084
          protocol      = "tcp"
          hostPort      = 8084
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/notification"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Notification service
resource "aws_ecs_service" "notification_service" {
  name             = "notification-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.notification_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.notification_service.arn
    container_name = "notification-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.notification_task

  ]
}


######Order Service

resource "aws_cloudwatch_log_group" "order" {
  name              = "/ecs/order"
  retention_in_days = 7

  tags = {
    Name = "order-logs"
  }
}


resource "aws_service_discovery_service" "order_service" {
  name = "order-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Order Task
resource "aws_ecs_task_definition" "order_task" {

  depends_on               = [aws_cloudwatch_log_group.order]
  family                   = "order"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "order-service"
      image     = var.order_image
      essential = true

      portMappings = [
        {
          containerPort = 8081
          protocol      = "tcp"
          hostPort      = 8081
        }
      ]

      environment = [
        {
          name  = "SQS_QUEUE_URL"
          value = var.main_queue_url
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/order"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Order service
resource "aws_ecs_service" "order_service" {
  name             = "order-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.order_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.order_service.arn
    container_name = "order-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.order_task

  ]
}


##Payment Service

resource "aws_cloudwatch_log_group" "payment" {
  name              = "/ecs/payment"
  retention_in_days = 7

  tags = {
    Name = "payment-logs"
  }
}


resource "aws_service_discovery_service" "payment_service" {
  name = "payment-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Payment Task
resource "aws_ecs_task_definition" "payment_task" {

  depends_on               = [aws_cloudwatch_log_group.payment]
  family                   = "payment"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "payment-service"
      image     = var.payment_image
      essential = true

      portMappings = [
        {
          containerPort = 8083
          protocol      = "tcp"
          hostPort      = 8083
        }
      ]

      environment = [
        {
          name  = "SQS_QUEUE_URL"
          value = var.main_queue_url
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/payment"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Payment service
resource "aws_ecs_service" "payment_api_service" {
  name             = "payment-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.payment_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.payment_service.arn
    container_name = "payment-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.payment_task

  ]
}


###Scheduler

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/ecs/scheduler"
  retention_in_days = 7

  tags = {
    Name = "scheduler-logs"
  }
}


resource "aws_service_discovery_service" "scheduler_service" {
  name = "scheduler-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Scheduler Task
resource "aws_ecs_task_definition" "scheduler_task" {

  depends_on               = [aws_cloudwatch_log_group.scheduler]
  family                   = "scheduler"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "scheduler-service"
      image     = var.scheduler_image
      essential = true

      portMappings = [
        {
          containerPort = 8091
          protocol      = "tcp"
          hostPort      = 8091
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/scheduler"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Scheduler  service

resource "aws_ecs_service" "scheduler_service" {
  name             = "scheduler-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.scheduler_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.scheduler_service.arn
    container_name = "scheduler-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.scheduler_task

  ]
}


####  Shipping

resource "aws_cloudwatch_log_group" "shipping" {
  name              = "/ecs/shipping"
  retention_in_days = 7

  tags = {
    Name = "shipping-logs"
  }
}


resource "aws_service_discovery_service" "shipping_service" {
  name = "shipping-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Shipping Task
resource "aws_ecs_task_definition" "shipping_task" {

  depends_on               = [aws_cloudwatch_log_group.shipping]
  family                   = "shipping"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "shipping-service"
      image     = var.shipping_image
      essential = true

      portMappings = [
        {
          containerPort = 8085
          protocol      = "tcp"
          hostPort      = 8085
        }
      ]

      environment = [
        {
          name  = "SQS_QUEUE_URL"
          value = var.main_queue_url
        }
      ]
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/shipping"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Shipping  service
resource "aws_ecs_service" "shipping_service" {
  name             = "shipping-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.shipping_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.shipping_service.arn
    container_name = "shipping-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.shipping_task

  ]
}




#############Worker 

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/worker"
  retention_in_days = 7

  tags = {
    Name = "worker-logs"
  }
}

resource "aws_service_discovery_service" "worker_service" {
  name = "worker-service"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }

}

##Worker Task
resource "aws_ecs_task_definition" "worker_task" {

  depends_on               = [aws_cloudwatch_log_group.worker]
  family                   = "worker"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.ecs_task_execution_role
  task_role_arn            = var.ecs_task_role

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "worker-service"
      image     = var.worker_image
      essential = true

      portMappings = [
        {
          containerPort = 8090
          protocol      = "tcp"
          hostPort      = 8090
        }
      ]

      environment = [
        {
          name  = "SQS_QUEUE_URL"
          value = var.main_queue_url
        }
      ]
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/worker"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Worker service
resource "aws_ecs_service" "worker_service" {
  name             = "worker-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.worker_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200

  deployment_circuit_breaker {
    enable = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.worker_service.arn
    container_name = "worker-service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.worker_task

  ]
}

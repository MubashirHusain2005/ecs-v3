data "aws_kms_key" "kms_key" {
  key_id = "alias/kms-ecr"
}

data "aws_secretsmanager_secret" "api_gateway_secret" {
  name = "JWT_SECRET"
}

##Need one for each service
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/my-ecs-task"
  retention_in_days = 7

  tags = {
    Name = "ecs-task-logs"
  }
}

##ECS Cluster
resource "aws_ecs_cluster" "ecsv3_cluster" {
  name = "ecs-cluster"

  configuration {
    execute_command_configuration {
      kms_key_id = data.aws_kms_key.kms_key.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_logs.name
      }
    }
  }
}


###Security Group

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "dashboard-api-sg"
  vpc_id      = var.vpc_id

}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.ecs_tasks.id

  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = "0.0.0.0/0"
}




###CloudMap Namespace

resource "aws_service_discovery_private_dns_namespace" "private" {
  name        = "${var.environment}.internal"
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

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
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

        { name = "REDIS_URL", value = "redis://${var.redis_url}:6379/0" },
        { name = "ORDER_SERVICE_URL", value = "http://order-service.${aws_service_discovery_private_dns_namespace.private.name}:8081" },
        { name = "API_INVENTORY_SERVICE_URL", value = "http://inventory-service.${aws_service_discovery_private_dns_namespace.private.name}:8082" },
        { name = "API_PAYMENTS_SERVICE_URL", value = "http://payment-service.${aws_service_discovery_private_dns_namespace.private.name}:8083" },
        { name = "API_NOTIFICATIONS_SERVICE_URL", value = "http://notification-service.${aws_service_discovery_private_dns_namespace.private.name}:8084" },
        { name = "API_SHIPPING_SERVICE_URL", value = "http://shipping-service.${aws_service_discovery_private_dns_namespace.private.name}:8085" },
        { name = "API_DASHBOARD_SERVICE_URL", value = "http://dashboard-api.${aws_service_discovery_private_dns_namespace.private.name}:8086" },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Api-gateway service
resource "aws_ecs_service" "api_gateway_service" {
  name             = "my-fargate-service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.api_gateway_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
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



##################################################################


##CloudMap Namespace Service

resource "aws_service_discovery_service" "dashboard_api_gateway" {
  name = "api-gateway"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private.id

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

##dashboard-api Task
resource "aws_ecs_task_definition" "dashboard_api_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

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
          name  = "DATABASE_URL"
          value = var.dashboard_db_url_secret_arn

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Api-gateway service
resource "aws_ecs_service" "dashboard_api_service" {
  name             = "dashboard_api_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.api_gateway_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.api_gateway.arn
    container_name = "dashboard_api"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}


##############################################

##CloudMap Namespace Service Inventory

resource "aws_service_discovery_service" "inventory_service" {
  name = "api-gateway"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Inventory Task
resource "aws_ecs_task_definition" "inventory_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "inventory-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/inventory_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Inventory service
resource "aws_ecs_service" "inventory_service" {
  name             = "inventory_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.inventory_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.inventory_service.arn
    container_name = "inventory_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}


###########Notification Service

resource "aws_service_discovery_service" "notification_service" {
  name = "notification-service"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Notification Task
resource "aws_ecs_task_definition" "notification_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "notification-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/notification_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Notification service
resource "aws_ecs_service" "notification_service" {
  name             = "notification_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.notification_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = [aws_service_discovery_service.inventory_service.arn]
    container_name = "inventory_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}


######Order Service


resource "aws_service_discovery_service" "order_service" {
  name = "order-service"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Order Task
resource "aws_ecs_task_definition" "order_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "order-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/order_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Order service
resource "aws_ecs_service" "order_service" {
  name             = "dashboard_api_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.order_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = [aws_service_discovery_service.inventory_service.arn]
    container_name = "inventory_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}




##Payment Service

resource "aws_service_discovery_service" "payment_service" {
  name = "payment-service"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Payment Task
resource "aws_ecs_task_definition" "payment_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "order-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/order_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Payment service
resource "aws_ecs_service" "payment_api_service" {
  name             = "payment_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.payment_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = [aws_service_discovery_service.inventory_service.arn]
    container_name = "payment_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}



###Scheduler


resource "aws_service_discovery_service" "scheduler_service" {
  name = "scheduler-service"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Scheduler Task
resource "aws_ecs_task_definition" "scheduler_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "order-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/scheduler_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Scheduler  service
resource "aws_ecs_service" "scheduler_service" {
  name             = "payment_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.scheduler_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = [aws_service_discovery_service.inventory_service.arn]
    container_name = "schduler_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}

####  Shipping

resource "aws_service_discovery_service" "shipping_service" {
  name = "shipping-service"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Shipping Task
resource "aws_ecs_task_definition" "shipping_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "shipping-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/shipping_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Shipping  service
resource "aws_ecs_service" "shipping_service" {
  name             = "payment_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.shipping_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = [aws_service_discovery_service.inventory_service.arn]
    container_name = "shipping_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}

#############Worker 


resource "aws_service_discovery_service" "worker_service" {
  name = "shipping-service"

  dns_config {
    namespace_id = [aws_service_discovery_private_dns_namespace.private.id]

    dns_records {
      ttl  = 10
      type = A
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 3
  }
}

##Worker Task
resource "aws_ecs_task_definition" "worker_task" {

  depends_on               = [aws_cloudwatch_log_group.ecs_logs]
  family                   = "service"
  network_mode             = var.network_mode
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "worker-service"
      image     = "125474112898.dkr.ecr.eu-west-2.amazonaws.com/worker_service:v1"
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
          name  = "DATABASE_URL"
          value = "${var.dashboard_db_url_secret_arn}:url::"

        },

      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/my-ecs-task"
          awslogs-region        = "eu-west-2"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

}

##Worker service
resource "aws_ecs_service" "worker_service" {
  name             = "worker_service"
  cluster          = aws_ecs_cluster.ecsv3_cluster.id
  task_definition  = aws_ecs_task_definition.worker_task.arn
  desired_count    = var.desired_count
  launch_type      = var.launch_type
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.alb_target_grp_arn
    container_name   = var.api_task_name
    container_port   = var.container_port
  }

  service_registries {
    registry_arn   = [aws_service_discovery_service.inventory_service.arn]
    container_name = "worker_service"

  }

  depends_on = [
    aws_ecs_cluster.ecsv3_cluster,
    aws_ecs_task_definition.api_gateway_task

  ]
}
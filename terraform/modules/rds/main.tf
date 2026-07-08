resource "aws_db_subnet_group" "dashboard_db" {
  name       = "dashboard-db-subnet-group"
  subnet_ids = var.private_subnet_ids # typically 2+ private subnets, different AZs

  tags = {
    Name = "dashboard-db-subnet-group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow inbound only from dashboard-api"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_sg]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_instance" "PostgreSQL_rds" {

  db_subnet_group_name        = aws_db_subnet_group.dashboard_db.name
  allocated_storage           = 10
  db_name                     = "mydb"
  engine                      = "postgres"
  engine_version              = "17.2"
  instance_class              = "db.t3.micro"
  username                    = "dashboard_app"
  parameter_group_name        = "default.postgres17"
  manage_master_user_password = true
  publicly_accessible         = false
  storage_encrypted           = true

  skip_final_snapshot       = true ##ideally false on prod environments
  final_snapshot_identifier = "rds-final-snapshot"
  multi_az                  = false

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

}

##Find the secret that RDS automatically created for this specific database instance
data "aws_secretsmanager_secret" "rds" {
  arn = aws_db_instance.PostgreSQL_rds.master_user_secret[0].secret_arn
}

data "aws_secretsmanager_secret_version" "rds" {
  secret_id = data.aws_secretsmanager_secret.rds.id
}
locals {
  db_credentials = jsondecode(
    data.aws_secretsmanager_secret_version.rds.secret_string
  )
}

resource "aws_secretsmanager_secret" "dashboard_db_url" {
  name = "dashboard-db-url"
}


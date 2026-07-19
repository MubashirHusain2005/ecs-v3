resource "aws_db_subnet_group" "dashboard_db" {
  name       = "dashboard-db-subnet-group"
  subnet_ids = var.private_subnet_ids 

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
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_instance" "PostgreSQL_rds" {

  db_subnet_group_name  = aws_db_subnet_group.dashboard_db.name
  allocated_storage     = 10
  db_name               = "mydb"
  max_allocated_storage = 100
  engine                = "postgres"
  engine_version        = "18.4"
  instance_class        = var.instance_class
  username              = "db_owner"
  password              = random_password.db_password.result
  publicly_accessible   = false
  storage_encrypted     = true

  skip_final_snapshot       = var.skip_final_snapshot ##ideally false on prod environments
  final_snapshot_identifier = "rds-final-snapshot"
  multi_az                  = var.multi_az #false in dev

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

}


resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&()*+,-.:;<=>?[]^_`{|}~"
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.environment}-rds-credentials"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    url = "postgresql://${aws_db_instance.PostgreSQL_rds.username}:${urlencode(random_password.db_password.result)}@${aws_db_instance.PostgreSQL_rds.address}:5432/${aws_db_instance.PostgreSQL_rds.db_name}"
  })
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = var.public_key
}

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}


resource "aws_instance" "prometheus" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = var.monitoring_instance_profile

  user_data = templatefile("${path.module}/prometheus.sh", {
  })

  timeouts {
    create = "2m"
  }

  tags = {
    Name = "prometheus-node"
  }
}


resource "aws_instance" "grafana" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = var.monitoring_instance_profile

  user_data = templatefile("${path.module}/grafana.sh", {
  })

  timeouts {
    create = "2m"
  }

  tags = {
    Name = "grafana-node"
  }
}


resource "aws_security_group" "monitoring_sg" {
  name   = "monitoring-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
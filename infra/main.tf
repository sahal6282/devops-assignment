terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ==========================================
# SECURITY GROUP
# ==========================================

resource "aws_security_group" "iii_microservices_sg" {
  name        = "iii-microservices-sg"
  description = "Allow SSH, HTTP API, and WebSocket traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# MICROSERVICE INSTANCES
# ==========================================

resource "aws_instance" "api_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.iii_microservices_sg.id]
  key_name               = var.key_name

  user_data = file("${path.module}/user-data/api.sh")

  tags = { Name = "iii-api-gateway" }
}
resource "aws_instance" "inference_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.iii_microservices_sg.id]
  key_name               = var.key_name

  root_block_device {
    volume_size           = 24
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data/inference.sh.tpl", {
    api_ip = aws_instance.api_vm.private_ip
  })

  depends_on = [aws_instance.api_vm]

  tags = { Name = "iii-inference-worker" }
}

resource "aws_instance" "caller_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.iii_microservices_sg.id]
  key_name               = var.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data/caller.sh.tpl", {
    api_ip = aws_instance.api_vm.private_ip
  })

  depends_on = [aws_instance.api_vm]

  tags = { Name = "iii-caller-worker" }
}

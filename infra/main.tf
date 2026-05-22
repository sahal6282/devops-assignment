terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---------------------------
# VPC & IGW
# ---------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "iii-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "iii-igw" }
}

# ---------------------------
# Subnets
# ---------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = { Name = "iii-public-subnet" }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "iii-private-subnet" }
}

# ---------------------------
# Security Groups
# ---------------------------
resource "aws_security_group" "api_sg" {
  name   = "api-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Allow inbound from the private subnet so it can route traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.2.0/24"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "internal_sg" {
  name   = "internal-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------
# EC2 Instances (Exactly 3)
# ---------------------------

# 1. API Gateway VM (Also acts as NAT)
resource "aws_instance" "api_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  # CRITICAL: This allows the API VM to act as a router for the private subnet
  source_dest_check = false

  user_data = file("${path.module}/user-data/api.sh")
  tags      = { Name = "iii-api-vm" }
}

# 2. Inference Worker VM
resource "aws_instance" "inference_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]
  user_data = templatefile("${path.module}/user-data/inference.sh", {
    api_ip = aws_instance.api_vm.private_ip
  })
  tags = { Name = "iii-inference-vm" }
}

# 3. Caller Worker VM
resource "aws_instance" "caller_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]
  user_data = templatefile("${path.module}/user-data/caller.sh", {
    api_ip       = aws_instance.api_vm.private_ip
    inference_ip = aws_instance.inference_vm.private_ip
  })
  tags = { Name = "iii-caller-vm" }
}

# ---------------------------
# Route Tables
# ---------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    # Point outbound internet traffic directly through the API VM
    network_interface_id = aws_instance.api_vm.primary_network_interface_id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

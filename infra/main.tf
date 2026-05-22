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

# =========================================================
# VPC & INTERNET GATEWAY
# =========================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "iii-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "iii-igw" }
}

# =========================================================
# SUBNETS
# =========================================================
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = { Name = "iii-public-subnet" }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"

  tags = { Name = "iii-private-subnet" }
}

# =========================================================
# SECURITY GROUPS
# =========================================================
resource "aws_security_group" "api_sg" {
  name   = "api-sg"
  vpc_id = aws_vpc.main.id

  # Public HTTP API
  ingress {
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Public SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound from Private Subnet (So API VM can route NAT traffic)
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

  # RPC & SSH allowed ONLY from within the VPC
  ingress {
    from_port   = 0
    to_port     = 65535
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

# =========================================================
# ROUTE TABLES
# =========================================================
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

  # Point outbound internet traffic directly through the API VM's Network Interface
  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.api_vm.primary_network_interface_id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# =========================================================
# EC2 INSTANCES
# =========================================================

# 1. API VM (Public Subnet + Acts as NAT Router)
resource "aws_instance" "api_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  # CRITICAL: Allows the API VM to act as a NAT router for the private subnet
  source_dest_check = false

  user_data = file("${path.module}/user-data/api.sh")

  tags = { Name = "iii-api-vm" }
}

# 2. INFERENCE VM (Private Subnet)
resource "aws_instance" "inference_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]

  # Expanded disk for the 2GB swap file and model weights
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data/inference.sh", {
    api_ip = aws_instance.api_vm.private_ip
  })

  tags = { Name = "iii-inference-vm" }
}

# 3. CALLER VM (Private Subnet)
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

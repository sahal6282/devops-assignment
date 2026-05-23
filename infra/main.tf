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
# 1. NETWORKING (VPC, Subnets, Gateways)
# ==========================================

resource "aws_vpc" "iii_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "iii-vpc" }
}

# Public Subnet (For the API Gateway & NAT)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.iii_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = { Name = "iii-public-subnet" }
}

# Private Subnet (For the Workers)
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.iii_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${var.region}a"
  tags                    = { Name = "iii-private-subnet" }
}

# Internet Gateway (Allows the Public Subnet to talk to the internet)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.iii_vpc.id
  tags   = { Name = "iii-igw" }
}

# Elastic IP & NAT Gateway (Allows Private Subnet to download packages)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags          = { Name = "iii-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.iii_vpc.id
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
  vpc_id = aws_vpc.iii_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# ==========================================
# 2. SECURITY GROUPS
# ==========================================

resource "aws_security_group" "api_sg" {
  name        = "iii-api-sg"
  description = "Allow inbound HTTP and SSH from the internet"
  vpc_id      = aws_vpc.iii_vpc.id

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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Add this block to allow the workers to connect to the engine!
  ingress {
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.iii_vpc.cidr_block]
  }
}

resource "aws_security_group" "worker_sg" {
  name        = "iii-worker-sg"
  description = "Allow internal RPC traffic from API and internal SSH"
  vpc_id      = aws_vpc.iii_vpc.id

  # Allow SSH ONLY from within the VPC (Jump Host)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.iii_vpc.cidr_block]
  }

  # Allow WebSocket traffic ONLY from the API Gateway Security Group
  ingress {
    from_port       = 49134
    to_port         = 49134
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 3. MICROSERVICE INSTANCES
# ==========================================

resource "aws_instance" "api_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]
  key_name               = var.key_name

  user_data = file("${path.module}/user-data/api.sh")

  tags = { Name = "iii-api-gateway" }
}

resource "aws_instance" "inference_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  key_name               = var.key_name

  root_block_device {
    volume_size           = 24
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data/inference.sh.tpl", {
    api_ip = aws_instance.api_vm.private_ip
  })

  depends_on = [aws_instance.api_vm, aws_nat_gateway.nat]

  tags = { Name = "iii-inference-worker" }
}

resource "aws_instance" "caller_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
  key_name               = var.key_name

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user-data/caller.sh.tpl", {
    api_ip = aws_instance.api_vm.private_ip
  })

  depends_on = [aws_instance.api_vm, aws_nat_gateway.nat]

  tags = { Name = "iii-caller-worker" }
}

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
# VPC & Internet Gateway
# ---------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iii-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iii-igw"
  }
}

# ---------------------------
# Subnets
# ---------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"

  tags = {
    Name = "iii-public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"

  tags = {
    Name = "iii-private-subnet"
  }
}

# ---------------------------
# Security Groups
# ---------------------------
resource "aws_security_group" "api_sg" {
  name   = "api-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP API"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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

resource "aws_security_group" "internal_sg" {
  name   = "internal-sg"
  vpc_id = aws_vpc.main.id

  # RPC port for iii workers
  ingress {
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # SSH inside VPC
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
# NAT Instance & Routing
# ---------------------------
resource "aws_instance" "nat_instance" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  # CRITICAL: Must be false for NAT routing to work
  source_dest_check = false

  tags = {
    Name = "iii-nat-instance"
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
              sysctl -p
              iptables -t nat -A POSTROUTING -o enX0 -j MASQUERADE || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              EOF
}

# Public Route Table (Points to Internet Gateway)
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

# Private Route Table (Points Outbound Traffic to NAT Instance)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat_instance.primary_network_interface_id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# ---------------------------
# EC2 Instances
# ---------------------------

# 1. API VM (Public Subnet)
resource "aws_instance" "api_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  user_data = file("${path.module}/user-data/api.sh")

  tags = {
    Name = "iii-api-vm"
  }
}

# 2. Inference Worker VM (Private Subnet) - MUST be t3.micro per your constraints
resource "aws_instance" "inference_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]

  # Inject the API VM's IP address so it can connect to the iii engine
  user_data = templatefile("${path.module}/user-data/inference.sh", {
    api_ip = aws_instance.api_vm.private_ip
  })

  tags = {
    Name = "iii-inference-vm"
  }
}

# 3. Caller Worker VM (Private Subnet)
resource "aws_instance" "caller_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]

  # Inject both IPs just in case your logic needs them
  user_data = templatefile("${path.module}/user-data/caller.sh", {
    api_ip       = aws_instance.api_vm.private_ip
    inference_ip = aws_instance.inference_vm.private_ip
  })

  tags = {
    Name = "iii-caller-vm"
  }
}

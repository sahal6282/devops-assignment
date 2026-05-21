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
# VPC
# ---------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iii-vpc"
  }
}

# ---------------------------
# Internet Gateway
# ---------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iii-igw"
  }
}

# ---------------------------
# Public Subnet (API VM)
# ---------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  availability_zone = "${var.region}a"

  tags = {
    Name = "iii-public-subnet"
  }
}

# ---------------------------
# Private Subnet (Workers)
# ---------------------------
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  availability_zone = "${var.region}a"

  tags = {
    Name = "iii-private-subnet"
  }
}

# ---------------------------
# Public Route Table
# ---------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "iii-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
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
# EC2 Instances
# ---------------------------

# API VM (Engine + HTTP + Caller Worker runs here OR you can split if needed)
resource "aws_instance" "api_vm" {
  ami           = var.ami_id
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]

  user_data = file("${path.module}/user-data/api.sh")

  tags = {
    Name = "iii-api-vm"
  }
}

# Caller Worker VM (Private)
resource "aws_instance" "caller_vm" {
  ami           = var.ami_id
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]

  user_data = file("${path.module}/user-data/caller.sh")

  tags = {
    Name = "iii-caller-vm"
  }
}

# Inference Worker VM (Private)
resource "aws_instance" "inference_vm" {
  ami           = var.ami_id
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.internal_sg.id]

  user_data = file("${path.module}/user-data/inference.sh")

  tags = {
    Name = "iii-inference-vm"
  }
}

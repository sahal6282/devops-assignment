variable "region" {
  description = "The AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS AMI for the target region"
  type        = string
  default     = "ami-07a00cf47dbbc844c"
}

variable "key_name" {
  description = "The name of your personal AWS SSH Key Pair"
  type        = string
  # No default value here! This forces the user to provide it in terraform.tfvars.
}

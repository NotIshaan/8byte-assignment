variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "8byte"
}

variable "project_name" {
  description = "project name used for naming and tagging resources"
  type        = string
  default     = "octabyte"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "cidr blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port"
  type        = number
  default     = 3000
}

variable "db_name" {
  description = "Postgres database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "postgres username"
  type        = string
  default     = "appadmin"
}

variable "db_password" {
  description = "postgres password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "alert_email" {
  description = "email for Cloudwatch alarm notifications"
  type        = string
  default     = ""
}

variable "ecr_image_url" {
  description = "ECR image URL"
  type        = string
}

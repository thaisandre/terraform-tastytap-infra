variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default        = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnets" {
  description = "List of CIDR blocks for private subnets"
  default     = ["10.0.2.0/24", "10.0.3.0/24"]
}

variable "cluster_name" {
  description = "Cluster name"
  default     = "tastytap-cluster"
}
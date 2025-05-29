
variable "ami_id" {
  description = "AMI ID for Ubuntu 16.04"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "key_name" {
  description = "Key pair name for SSH access"
  type        = string
}

variable "eks_cidr" {
  description = "CIDR block of the EKS cluster"
  type        = string
}
variable "s3_bucket_name" {
  description = "S3 bucket name for MongoDB backups"
  type        = string
}
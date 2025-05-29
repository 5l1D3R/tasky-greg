variable "region" {
  default = "us-east-1"
}
variable "cluster_name" {
  default = "greg-wiz-cluster-terraform"
}
variable "image_url" {}
variable "secret_key" {}
variable "ami_id" {}
variable "instance_type" {}
variable "subnet_id" {}
variable "vpc_id" {}
variable "key_name" {}
variable "eks_cidr" {}
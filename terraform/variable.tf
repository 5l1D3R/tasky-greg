variable "region" {
  default = "us-east-1"
}
variable "cluster_name" {
  default = "greg-wiz-cluster"
}
variable "mongo_uri" {
  sensitive = true
}
variable "image_url" {}
variable "secret_key" {
  sensitive = true
}
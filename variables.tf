
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_region" {
  default = "eu-central-1"
}
variable "aws_spot_price" {
  default = "0.02"
}
variable "aws_instance_type" {
  default = "t2.medium"
}
variable "aws_ami" {
  # Ubuntu 16.04 LTS
  default = "ami-05af84768964d3dc0"
}
variable "ssh_key_path" {
  default = "~/.ssh/id_rsa.pub"
}
variable "docker_version" {
  default = "18.09.2"
}

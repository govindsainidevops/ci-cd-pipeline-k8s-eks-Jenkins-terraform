variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "devops-cluster"
}

variable "ecr_repo_name" {
  default = "devops-app"
}

variable "node_instance_type" {
  default = "t3.small"
}

variable "desired_nodes" {
  default = 2
}
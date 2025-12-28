variable "aws_region" {
  description = "AWS region where computation & storage occurs"
  type        = string
  default     = "us-west-1"
}

variable "eks_cluster_name" {
  description = "Name of the lambda function"
  type        = string
  default     = "KubeSiteCluster"
}

variable "cluster_role_name" {
  description = "Name of the role that lambda needs"
  type        = string
  default = "AmazonEKSClusterRole"
}

variable "cluster_node_role_name" {
  description = "Name of the role that lambda needs"
  type        = string
  default = "AmazonEKSNodeRole"
}

variable "ecr_repo_name" {
  description = "Name of ecr repository"
  type        = string
  default = "nginx-texsite"
}

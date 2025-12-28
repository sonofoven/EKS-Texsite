### Define terraform setup & vars

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}

provider "aws" {
  region = var.aws_region
}


### Provision all resources for EKS ###

## Define cluster role and attach necessary roles
data "aws_iam_policy_document" "cluster_assume_role"{
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_role"{
  name = var.cluster_role_name
  description = "Enables eks cluster to be in auto mode"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role
}

resource "aws_iam_role_policy_attachment" "attachments" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
  ])

  role       = aws_iam_role.cluster_role.name
  policy_arn = each.value
}


## Define worker node role and attach necessary roles
data "aws_iam_policy_document" "worker_node_assume_role"{
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker_node_role"{
  name = var.cluster_role_name
  description = "Enables ec2 node to be part of eks cluster & use ecr"
  assume_role_policy = data.aws_iam_policy_document.worker_node_assume_role
}

resource "aws_iam_role_policy_attachment" "attachments" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
  ])

  role       = aws_iam_role.worker_node_role.name
  policy_arn = each.value
}


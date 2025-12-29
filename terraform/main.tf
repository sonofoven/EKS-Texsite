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

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.id
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

resource "aws_iam_role" "cluster"{
  name = var.cluster_role_name
  description = "Enables eks cluster to be in auto mode"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cluster_attachments" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
  ])

  role       = aws_iam_role.cluster.name
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

resource "aws_iam_role" "worker_node"{
  name = var.cluster_node_role_name
  description = "Enables ec2 node to be part of eks cluster & use ecr"
  assume_role_policy = data.aws_iam_policy_document.worker_node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "worker_node_attachments" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
  ])

  role       = aws_iam_role.worker_node.name
  policy_arn = each.value
}

## Create ECR
resource "aws_ecr_repository" "nginx-texsite" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

## Create networking environment

# Create subnets
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
}

resource "aws_subnet" "az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}c"
}

# Create public subnet
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

# Internet gateway for pub subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Elastic ip for NAT gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# Connect nat gateway to pub subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_az1.id
  depends_on    = [aws_internet_gateway.igw]
}

# Pub routing table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Connect pub routing table to pub subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

# Priv routing table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

# Connect priv routing table to priv subnet
resource "aws_route_table_association" "az1" {
  subnet_id      = aws_subnet.az1.id
  route_table_id = aws_route_table.private.id
}

# Connect priv routing table to priv subnet
resource "aws_route_table_association" "az2" {
  subnet_id      = aws_subnet.az2.id
  route_table_id = aws_route_table.private.id
}


## Create a role for the user to assume to access eks
resource "aws_iam_role" "eks_access" {
  name = var.eks_access_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${local.account_id}:root"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

## Create an access entry & policy associations for devs to access eks


# Access entry
resource "aws_eks_access_entry" "eks_access" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.eks_access.arn
  depends_on = [ aws_eks_cluster.nginx-texsite ]
}


# Allow devs to modify the cluster
resource "aws_eks_access_policy_association" "eks_access_edit" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.eks_access.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope { type = "cluster" }

  depends_on = [ aws_eks_access_entry.eks_access ]
}

# Allow devs to view kube info
resource "aws_eks_access_policy_association" "eks_access_view" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.eks_access.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["kube-system"]
  }
  depends_on = [ aws_eks_access_entry.eks_access ]
}

## Create EKS 
resource "aws_eks_cluster" "nginx-texsite" {
  name = var.eks_cluster_name

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster.arn
  version  = "1.32"

  bootstrap_self_managed_addons = false

  compute_config {
    enabled       = true
    node_pools    = ["general-purpose"]
    node_role_arn = aws_iam_role.worker_node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true

    subnet_ids = [
      aws_subnet.az1.id,
      aws_subnet.az2.id,
    ]
  }

  # Ensure that IAM Role permissions are created before
  depends_on = [
    aws_iam_role_policy_attachment.cluster_attachments,
    aws_iam_role_policy_attachment.worker_node_attachments,
  ]
}

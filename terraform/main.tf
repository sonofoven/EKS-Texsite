### Define terraform setup & vars

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
    tls = {
      source = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
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
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = var.cluster_role_name
  description        = "Enables eks cluster to be in auto mode"
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
data "aws_iam_policy_document" "worker_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker_node" {
  name               = var.cluster_node_role_name
  description        = "Enables ec2 node to be part of eks cluster & use ecr"
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
  force_delete         = true

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
  tags = {
      "kubernetes.io/role/internal-elb"               = "1"
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }
}

resource "aws_subnet" "az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}c"
  tags = {
      "kubernetes.io/role/internal-elb"               = "1"
      "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }
}

# Create public subnets
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "${var.aws_region}a"

  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "${var.aws_region}c"

  map_public_ip_on_launch = true
  tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }
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
resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
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
  depends_on    = [aws_eks_cluster.nginx-texsite]
}


# Allow devs to modify the cluster
resource "aws_eks_access_policy_association" "eks_access_edit" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_iam_role.eks_access.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope { type = "cluster" }

  depends_on = [aws_eks_access_entry.eks_access]
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
  depends_on = [aws_eks_access_entry.eks_access]
}

## Create EKS 
resource "aws_eks_cluster" "nginx-texsite" {
  name = var.eks_cluster_name

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster.arn
  version  = "1.33"

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

## Create IRSA (IAM Role for Service Account)


# Collect data for policy document
data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
  depends_on = [aws_eks_cluster.nginx-texsite]
}

# Need a tls cert for openconnect
data "tls_certificate" "oidc" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}


# Policy document to allow trust
data "aws_iam_policy_document" "repo_monitor_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.this.arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:flux-system:image-reflector-controller"
      ]
    }
  }
}

# Create policy to enable ecr reading
resource "aws_iam_policy" "ecr_read" {
  name = "FluxECRReadOnly"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages",
        "ecr:ListImages"
      ]
      Resource = "*"
    }]
  })
}

# Attach above policy to role
resource "aws_iam_role_policy_attachment" "attach_ecr" {
  role       = aws_iam_role.repo_monitor.name
  policy_arn = aws_iam_policy.ecr_read.arn
}

# Create role
resource "aws_iam_role" "repo_monitor" {
  name               = "image-reflector-role"
  assume_role_policy = data.aws_iam_policy_document.repo_monitor_assume_role.json
}




# Get policy json to make ALB's
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# Make alb policy
resource "aws_iam_policy" "lbc_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Permissions for EKS Load Balancer Controller"
  policy      = data.http.lbc_iam_policy.response_body
}

# Create the trust policy, trusting only the service
data "aws_iam_policy_document" "lbc_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.this.arn]
      type        = "Federated"
    }
  }
}

# Create the role
resource "aws_iam_role" "lbc_role" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume_role_policy.json
}

# Connect policy to the role
resource "aws_iam_role_policy_attachment" "lbc_attach" {
  role       = aws_iam_role.lbc_role.name
  policy_arn = aws_iam_policy.lbc_policy.arn
}

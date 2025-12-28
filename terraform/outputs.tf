output "ecr_repository_url" {
  value = aws_ecr_repository.nginx-texsite.repository_url
}

output "eks_cluster_name" {
  value = var.eks_cluster_name
}

output "aws_region" {
  value = var.aws_region
}


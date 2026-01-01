output "ecr_repository_url" {
  value = aws_ecr_repository.nginx-texsite.repository_url
}

output "eks_cluster_name" {
  value = var.eks_cluster_name
}

output "aws_region" {
  value = var.aws_region
}

output "eks_role_arn" {
  value = aws_iam_role.eks_access.arn
}

output "repo_monitor_role_arn" {
  value = aws_iam_role.repo_monitor.arn
}

output "alb_role_arn" {
  value = aws_iam_role.lbc_role.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}

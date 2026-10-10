# Reference existing EKS cluster — no new cluster created
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}

# Reuse existing GitHub OIDC provider (created by gitops-eks-platform)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Cluster OIDC provider for IRSA (created alongside the cluster)
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Existing public hosted zone for preview hostnames
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

locals {
  eks_oidc_host = replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
  preview_zone  = "preview.${trimsuffix(data.aws_route53_zone.main.name, ".")}"
}

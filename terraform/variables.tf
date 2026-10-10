variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  description = "Existing EKS cluster name (from gitops-eks-platform)."
  type        = string
  default     = "gitops-eks"
}

variable "github_repo" {
  description = "GitHub repo in org/repo format for OIDC trust."
  type        = string
  default     = "REPLACE_ME/pr-preview-envs"
}

variable "hosted_zone_name" {
  description = "Existing public Route53 hosted zone. Previews are served at pr-<N>.preview.<zone>."
  type        = string
  default     = "REPLACE_ME_example.com"
}

variable "ingress_lb_hostname" {
  description = <<-EOT
    DNS name of the ingress-nginx NLB the wildcard record points at. Look it up with:
      kubectl -n ingress-nginx get svc ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
  EOT
  type        = string
  default     = "REPLACE_ME.elb.us-east-1.amazonaws.com"
}

variable "ecr_repositories" {
  description = "ECR repositories for preview images."
  type        = list(string)
  default     = ["preview-backend", "preview-frontend"]
}

variable "max_pr_images" {
  description = "Max number of pr- tagged images kept per repository."
  type        = number
  default     = 50
}

variable "deployer_k8s_group" {
  description = "Kubernetes RBAC group the GitHub Actions role maps to (ClusterRole binding lives in platform/)."
  type        = string
  default     = "preview-deployers"
}

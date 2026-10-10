# ---------------------------------------------------------------------------
# GitHub Actions role (OIDC) — builds/pushes images, deploys previews
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_actions" {
  name = "pr-preview-envs-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions" {
  name = "pr-preview-envs-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushAndPrune"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchDeleteImage",
          "ecr:ListImages",
          "ecr:DescribeImages",
        ]
        Resource = [for r in aws_ecr_repository.preview : r.arn]
      },
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = data.aws_eks_cluster.main.arn
      },
    ]
  })
}

# Map the CI role into the cluster as a member of the preview-deployers group.
# No access policy association: permissions come from the preview-deployer
# ClusterRole + bindings in platform/ (scoped RBAC, not cluster-admin).
resource "aws_eks_access_entry" "github_actions" {
  cluster_name      = data.aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.github_actions.arn
  kubernetes_groups = [var.deployer_k8s_group]
  type              = "STANDARD"
}

# ---------------------------------------------------------------------------
# IRSA role for cert-manager — DNS-01 solver for the wildcard certificate
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cert_manager" {
  name = "pr-preview-envs-cert-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.eks_oidc_host}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          "${local.eks_oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cert_manager" {
  name = "pr-preview-envs-cert-manager-route53"
  role = aws_iam_role.cert_manager.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Route53GetChange"
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Sid    = "Route53ZoneRecords"
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
        ]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
      },
      {
        Sid      = "Route53ListZones"
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = "*"
      },
    ]
  })
}

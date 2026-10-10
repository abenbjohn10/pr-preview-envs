output "ecr_registry" {
  description = "Set as the ECR_REGISTRY GitHub variable."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.preview : k => r.repository_url }
}

output "github_actions_role_arn" {
  description = "Set as the IAM_ROLE_ARN GitHub variable."
  value       = aws_iam_role.github_actions.arn
}

output "cert_manager_role_arn" {
  description = "IRSA role ARN for the cert-manager ServiceAccount annotation (platform/)."
  value       = aws_iam_role.cert_manager.arn
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID for the ClusterIssuer DNS-01 solver (platform/)."
  value       = data.aws_route53_zone.main.zone_id
}

output "preview_domain" {
  description = "Set as the PREVIEW_DOMAIN GitHub variable (previews: pr-<N>.preview.<this>)."
  value       = trimsuffix(data.aws_route53_zone.main.name, ".")
}

output "preview_wildcard_record" {
  value = aws_route53_record.preview_wildcard.fqdn
}

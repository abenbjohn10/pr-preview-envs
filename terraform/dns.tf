# Single wildcard record → ingress-nginx NLB. Every pr-<N>.preview.<zone>
# resolves instantly with no per-PR DNS churn (no external-dns needed).
#
# Find the NLB hostname with:
#   kubectl -n ingress-nginx get svc ingress-nginx-controller \
#     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
resource "aws_route53_record" "preview_wildcard" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "*.${local.preview_zone}"
  type    = "CNAME"
  ttl     = 300
  records = [var.ingress_lb_hostname]
}

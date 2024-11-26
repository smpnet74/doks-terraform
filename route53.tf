# Use the existing Route53 zone
data "aws_route53_zone" "domain" {
  zone_id = "Z2GRRZM0LLXUTR"  # Existing zone ID for domainsandbox.net
}

# Get the Load Balancer hostname from the ingress-nginx service
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [module.eks_blueprints_addons]
}

# Create a wildcard record for subdomains
resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = "*.${data.aws_route53_zone.domain.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname]

  depends_on = [data.kubernetes_service.ingress_nginx]
}

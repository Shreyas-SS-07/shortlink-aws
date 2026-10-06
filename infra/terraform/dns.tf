# HTTPS: ACM certificate + Route 53 DNS validation + ALB alias record.
# Set enable_https = true and domain_name / route53_zone_id in terraform.tfvars.
# Leave enable_https = false (default) if you have no domain yet.

# ── ACM certificate (must be in same region as ALB, ap-south-1) ─────────────
resource "aws_acm_certificate" "main" {
  count             = var.enable_https ? 1 : 0
  domain_name       = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }
}

# ── DNS validation CNAME records ─────────────────────────────────────────────
resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_https ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "main" {
  count                   = var.enable_https ? 1 : 0
  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ── Route 53 A record → ALB ──────────────────────────────────────────────────
resource "aws_route53_record" "alb" {
  count   = var.enable_https ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# ── Route 53 A record → CloudFront (when CDN is enabled) ────────────────────
resource "aws_route53_record" "cdn" {
  count   = (var.enable_https && var.enable_cloudfront) ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main[0].domain_name
    zone_id                = aws_cloudfront_distribution.main[0].hosted_zone_id
    evaluate_target_health = false
  }

  # When CloudFront is enabled, it replaces the direct ALB record.
  depends_on = [aws_route53_record.alb]

  lifecycle { create_before_destroy = true }
}

# CloudFront distribution in front of the ALB.
# Guards behind enable_cloudfront variable — works with or without HTTPS.
#
# ACM cert for CloudFront MUST be in us-east-1 (CloudFront requirement).
# We provision a separate cert there using a provider alias.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# ── ACM cert in us-east-1 for CloudFront ─────────────────────────────────────
resource "aws_acm_certificate" "cdn" {
  count             = (var.enable_cloudfront && var.enable_https) ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

# DNS validation records for the us-east-1 cert (route53 is global, no alias needed)
resource "aws_route53_record" "cdn_cert_validation" {
  for_each = (var.enable_cloudfront && var.enable_https) ? {
    for dvo in aws_acm_certificate.cdn[0].domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "cdn" {
  count                   = (var.enable_cloudfront && var.enable_https) ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cdn[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cdn_cert_validation : r.fqdn]
}

# ── CloudFront distribution ───────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  count   = var.enable_cloudfront ? 1 : 0
  enabled = true
  comment = "${var.project} CDN — caches popular redirects at the edge"
  aliases = (var.enable_https && var.domain_name != "") ? [var.domain_name] : []

  # Origin: the ALB
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = var.enable_https ? "https-only" : "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 60
      origin_keepalive_timeout = 5
    }

    # Forward the real Host header so ALB routes correctly
    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name != "" ? var.domain_name : aws_lb.main.dns_name
    }
  }

  # Cache behaviour for redirect endpoints (/{code}) — short TTL, pass-through
  # AWS Managed CachingDisabled policy: no caching, full pass-through
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    # CachingDisabled managed policy (redirects must not be cached at CDN level —
    # each hit must reach the app to count the click)
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # AllViewer: forward all headers, cookies, query strings to origin
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"

    compress               = true
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # Viewer certificate
  viewer_certificate {
    dynamic "acm_certificate" {
      # pseudo-block trick — we inline the attributes instead:
      for_each = []
      content {}
    }
    # Use acm_certificate_arn attribute directly:
    acm_certificate_arn      = (var.enable_cloudfront && var.enable_https) ? aws_acm_certificate_validation.cdn[0].certificate_arn : null
    cloudfront_default_certificate = (var.enable_cloudfront && !var.enable_https) ? true : false
    ssl_support_method       = (var.enable_cloudfront && var.enable_https) ? "sni-only" : null
    minimum_protocol_version = (var.enable_cloudfront && var.enable_https) ? "TLSv1.2_2021" : "TLSv1"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_100" # US, EU, Asia — cheapest class

  tags = { Name = "${var.project}-cdn" }
}

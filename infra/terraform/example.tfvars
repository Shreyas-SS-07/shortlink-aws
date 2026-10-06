# terraform apply -var-file=terraform.tfvars
region             = "ap-south-1" # AWS Region
project            = "shortlink"
db_multi_az        = false        # set true for the multi-AZ RDS failover demo
single_nat_gateway = true         # set false for high availability across both AZs (adds cost)
asg_min            = 2
asg_max            = 6

# ── HTTPS & Custom Domain (Optional) ─────────────────────────────────────────
# enable_https     = true
# domain_name      = "short.yourdomain.com"
# route53_zone_id  = "Z0123456789ABCDEF"

# ── CloudFront CDN (Optional) ────────────────────────────────────────────────
# enable_cloudfront = true

# ── CloudWatch Observability & SNS Alerts (Optional) ────────────────────────
# alert_email      = "you@example.com" # Receives email alerts for 5xx, latency, CPU spikes

# ── Serverless Click Event Pipeline: SQS → Lambda → DynamoDB (Optional) ─────
# enable_pipeline  = true

# ── GitHub Actions OIDC Deploy Role (Optional) ──────────────────────────────
# Set to your GitHub username / org to create a secure passwordless IAM role
# github_org       = "your-github-username"
# github_repo      = "shortlink-aws"

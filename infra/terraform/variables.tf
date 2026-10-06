variable "region" {
  type    = string
  default = "ap-south-1" # Mumbai: closest region for you
}

variable "project" {
  type    = string
  default = "shortlink"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 6
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Standby replica in a second AZ. Doubles DB cost; turn on for the failover demo."
  type        = bool
  default     = false
}

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "single_nat_gateway" {
  description = "One NAT for all AZs (cheap) vs one per AZ (highly available)."
  type        = bool
  default     = true
}

# ── HTTPS / DNS ───────────────────────────────────────────────────────────────
variable "enable_https" {
  description = "Create ACM cert, HTTPS ALB listener, and HTTP→HTTPS redirect. Requires domain_name and route53_zone_id."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Apex domain for HTTPS and CloudFront, e.g. shortlink.yourdomain.com"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for domain_name. Find it in the Route 53 console."
  type        = string
  default     = ""
}

# ── CloudFront CDN ────────────────────────────────────────────────────────────
variable "enable_cloudfront" {
  description = "Deploy a CloudFront distribution in front of the ALB."
  type        = bool
  default     = false
}

# ── Observability ─────────────────────────────────────────────────────────────
variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications. Leave empty to skip the SNS email subscription."
  type        = string
  default     = ""
}

# ── Serverless click pipeline ─────────────────────────────────────────────────
variable "enable_pipeline" {
  description = "Deploy the SQS → Lambda → DynamoDB click event pipeline."
  type        = bool
  default     = false
}

# ── GitHub OIDC ───────────────────────────────────────────────────────────────
variable "github_org" {
  description = "GitHub username or organisation that owns the repo. Set to enable the OIDC role."
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix)."
  type        = string
  default     = "shortlink-aws"
}

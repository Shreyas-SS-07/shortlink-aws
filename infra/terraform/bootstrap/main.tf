terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  # Bootstrap uses local state intentionally (chicken-and-egg).
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "shortlink"
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# ── S3 bucket for Terraform state ────────────────────────────────────────────
resource "aws_s3_bucket" "tf_state" {
  bucket        = "${var.project}-tf-state-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = { Name = "${var.project}-tf-state", Managed = "terraform" }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB lock table ───────────────────────────────────────────────────────
resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Name = "${var.project}-tf-lock", Managed = "terraform" }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "state_bucket" { value = aws_s3_bucket.tf_state.bucket }
output "lock_table"   { value = aws_dynamodb_table.tf_lock.name }

output "backend_config" {
  value = <<-EOT
    # Copy this into infra/terraform/versions.tf (replace the backend "s3" {} stub):
    backend "s3" {
      bucket         = "${aws_s3_bucket.tf_state.bucket}"
      key            = "shortlink/terraform.tfstate"
      region         = "${var.region}"
      dynamodb_table = "${aws_dynamodb_table.tf_lock.name}"
      encrypt        = true
    }
  EOT
}

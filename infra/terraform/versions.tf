terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Remote state — Week 3 upgrade.
  # Steps:
  #   1. cd infra/terraform/bootstrap && terraform init && terraform apply
  #   2. Copy the backend_config output value into the block below.
  #   3. terraform init -migrate-state  (migrates local .tfstate to S3)
  #
  # backend "s3" {
  #   bucket         = "shortlink-tf-state-<account-id>"
  #   key            = "shortlink/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "shortlink-tf-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project = var.project
      Managed = "terraform"
    }
  }
}

# us-east-1 alias: required for CloudFront ACM certificates.
# CloudFront only accepts certs issued in us-east-1, regardless of app region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project = var.project
      Managed = "terraform"
    }
  }
}

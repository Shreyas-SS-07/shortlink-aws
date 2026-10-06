# GitHub OIDC – lets GitHub Actions assume an AWS role without long-lived keys.
# After `terraform apply`, copy the output role ARN into the repo secret AWS_ROLE_ARN.

variable "github_org" {
  description = "GitHub username or organisation that owns the repo."
  type        = string
  default     = ""  # set in terraform.tfvars: github_org = "your-username"
}

variable "github_repo" {
  description = "Repo name (without the org prefix)."
  type        = string
  default     = "shortlink-aws"
}

# GitHub's OIDC thumbprint (SHA-1 of the root CA cert – stable, published by GitHub).
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.github_org != "" ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1",
                     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_policy_document" "github_assume" {
  count = var.github_org != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count              = var.github_org != "" ? 1 : 0
  name               = "${var.project}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json
}

data "aws_iam_policy_document" "github_actions" {
  count = var.github_org != "" ? 1 : 0

  # ECR: push images
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
  # ASG: trigger rolling instance refresh
  statement {
    actions   = ["autoscaling:StartInstanceRefresh", "autoscaling:DescribeInstanceRefreshes"]
    resources = [aws_autoscaling_group.app.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  count  = var.github_org != "" ? 1 : 0
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions[0].json
}

output "github_actions_role_arn" {
  description = "Paste this into GitHub repo secret: AWS_ROLE_ARN"
  value       = var.github_org != "" ? aws_iam_role.github_actions[0].arn : "Set github_org variable to enable"
}

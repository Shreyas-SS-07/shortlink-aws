output "alb_url" {
  value = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "cloudfront_url" {
  description = "CloudFront distribution URL (if enabled)"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.main[0].domain_name}" : "CloudFront disabled"
}

output "domain_url" {
  description = "Custom domain URL (if HTTPS enabled)"
  value       = var.enable_https ? "https://${var.domain_name}" : "HTTPS disabled"
}

output "dashboard_url" {
  description = "CloudWatch dashboard — open this after deploy"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.project}"
}

output "github_actions_role_arn" {
  description = "Copy this into GitHub repo secret AWS_ROLE_ARN"
  value       = var.github_org != "" ? aws_iam_role.github_actions[0].arn : "Set github_org variable to enable"
}

output "clicks_pipeline_queue" {
  description = "SQS queue URL for the click event pipeline (if enabled)"
  value       = var.enable_pipeline ? aws_sqs_queue.clicks[0].url : "Pipeline disabled"
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

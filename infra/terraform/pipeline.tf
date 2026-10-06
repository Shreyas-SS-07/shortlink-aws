# Serverless click pipeline: SQS → Lambda → DynamoDB.
# Each redirect publishes an event to SQS (fire-and-forget).
# Lambda consumes the queue in batches and writes per-click records to DynamoDB.
# This runs in parallel with the Redis INCR counter — they serve different purposes:
#   Redis INCR → fast aggregate count on the /stats endpoint
#   DynamoDB   → raw per-click event log (future analytics, funnels, geographic breakdown)
#
# Toggle with enable_pipeline = true in terraform.tfvars.

# ── SQS queues ────────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "clicks_dlq" {
  count                     = var.enable_pipeline ? 1 : 0
  name                      = "${var.project}-clicks-dlq"
  message_retention_seconds = 1209600 # 14 days — time to investigate failures
}

resource "aws_sqs_queue" "clicks" {
  count                      = var.enable_pipeline ? 1 : 0
  name                       = "${var.project}-clicks"
  visibility_timeout_seconds = 300   # must be >= Lambda timeout
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.clicks_dlq[0].arn
    maxReceiveCount     = 3
  })
}

# App instances need permission to send to this queue
resource "aws_sqs_queue_policy" "clicks" {
  count     = var.enable_pipeline ? 1 : 0
  queue_url = aws_sqs_queue.clicks[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.app.arn }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.clicks[0].arn
    }]
  })
}

# ── DynamoDB table — raw click events ─────────────────────────────────────────
resource "aws_dynamodb_table" "click_events" {
  count        = var.enable_pipeline ? 1 : 0
  name         = "${var.project}-click-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "link_code"
  range_key    = "ts"

  attribute {
    name = "link_code"
    type = "S"
  }
  attribute {
    name = "ts"
    type = "N" # Unix epoch milliseconds
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Name = "${var.project}-click-events" }
}

# ── Lambda IAM role ───────────────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  count = var.enable_pipeline ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_click" {
  count              = var.enable_pipeline ? 1 : 0
  name               = "${var.project}-lambda-click"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume[0].json
}

data "aws_iam_policy_document" "lambda_click" {
  count = var.enable_pipeline ? 1 : 0

  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"]
    resources = [aws_dynamodb_table.click_events[0].arn]
  }
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [aws_sqs_queue.clicks[0].arn]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_click" {
  count  = var.enable_pipeline ? 1 : 0
  role   = aws_iam_role.lambda_click[0].id
  policy = data.aws_iam_policy_document.lambda_click[0].json
}

# ── Lambda function ───────────────────────────────────────────────────────────
data "archive_file" "click_consumer" {
  count       = var.enable_pipeline ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/../lambda/click-consumer"
  output_path = "${path.module}/../lambda/click-consumer.zip"
}

resource "aws_lambda_function" "click_consumer" {
  count            = var.enable_pipeline ? 1 : 0
  filename         = data.archive_file.click_consumer[0].output_path
  source_code_hash = data.archive_file.click_consumer[0].output_base64sha256
  function_name    = "${var.project}-click-consumer"
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.lambda_click[0].arn
  timeout          = 300
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.click_events[0].name
      REGION         = var.region
    }
  }
}

# SQS event source mapping: Lambda polls the queue automatically
resource "aws_lambda_event_source_mapping" "clicks" {
  count            = var.enable_pipeline ? 1 : 0
  event_source_arn = aws_sqs_queue.clicks[0].arn
  function_name    = aws_lambda_function.click_consumer[0].arn
  batch_size       = 100
  # Lambda receives up to 100 click events per invocation
}

# ── Grant app EC2 role permission to send to SQS ─────────────────────────────
resource "aws_iam_role_policy" "app_sqs" {
  count = var.enable_pipeline ? 1 : 0
  role  = aws_iam_role.app.id
  name  = "sqs-clicks"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
      Resource = aws_sqs_queue.clicks[0].arn
    }]
  })
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "clicks_queue_url" {
  value = var.enable_pipeline ? aws_sqs_queue.clicks[0].url : "Pipeline disabled"
}

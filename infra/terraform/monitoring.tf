# CloudWatch: SNS topic, 6 alarms, and a dashboard.
# Set alert_email in terraform.tfvars to receive alarm notifications.

# ── SNS topic for all alarms ──────────────────────────────────────────────────
resource "aws_sns_topic" "alarms" {
  name = "${var.project}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Alarm 1: ALB 5xx errors ───────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  treat_missing_data  = "notBreaching"
  alarm_description   = "More than 20 ALB 5xx errors in 5 minutes."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# ── Alarm 2: ALB p99 latency ──────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_p99" {
  alarm_name          = "${var.project}-alb-p99-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 2.0
  treat_missing_data  = "notBreaching"
  alarm_description   = "ALB p99 latency exceeded 2 seconds."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# ── Alarm 3: ASG CPU ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "${var.project}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "ASG average CPU above 80% for 15 minutes."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# ── Alarm 4: RDS connections ──────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.project}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "RDS connection count above 80. Check for connection leaks."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

# ── Alarm 5: ElastiCache connections ─────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "redis_connections" {
  alarm_name          = "${var.project}-redis-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 500
  treat_missing_data  = "notBreaching"
  alarm_description   = "ElastiCache connection count above 500."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    CacheClusterId = "${var.project}-redis-0001"
  }
}

# ── Alarm 6: RDS CPU ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "RDS CPU above 80%. Consider adding a read replica."
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

# ── CloudWatch dashboard ──────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: ALB metrics
      {
        type   = "metric"
        x      = 0; y = 0; width = 8; height = 6
        properties = {
          title   = "ALB — Requests / 5 min"
          view    = "timeSeries"
          region  = var.region
          period  = 300
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",
              "LoadBalancer", aws_lb.main.arn_suffix,
              { label = "Requests" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8; y = 0; width = 8; height = 6
        properties = {
          title  = "ALB — 5xx Errors"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
              "LoadBalancer", aws_lb.main.arn_suffix,
              { label = "5xx", color = "#d62728" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16; y = 0; width = 8; height = 6
        properties = {
          title  = "ALB — Redirect Latency (seconds)"
          view   = "timeSeries"
          region = var.region
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", aws_lb.main.arn_suffix,
              { stat = "p99", label = "p99", color = "#d62728" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", aws_lb.main.arn_suffix,
              { stat = "p95", label = "p95", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "TargetResponseTime",
              "LoadBalancer", aws_lb.main.arn_suffix,
              { stat = "p50", label = "p50", color = "#1f77b4" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },

      # Row 2: EC2 + RDS + Redis
      {
        type   = "metric"
        x      = 0; y = 6; width = 8; height = 6
        properties = {
          title  = "ASG — CPU Utilization %"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization",
              "AutoScalingGroupName", aws_autoscaling_group.app.name,
              { label = "CPU %" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 8; y = 6; width = 8; height = 6
        properties = {
          title  = "RDS — Connections + CPU"
          view   = "timeSeries"
          region = var.region
          period = 300
          metrics = [
            ["AWS/RDS", "DatabaseConnections",
              "DBInstanceIdentifier", aws_db_instance.main.id,
              { stat = "Average", label = "Connections", yAxis = "left" }],
            ["AWS/RDS", "CPUUtilization",
              "DBInstanceIdentifier", aws_db_instance.main.id,
              { stat = "Average", label = "CPU %", yAxis = "right" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16; y = 6; width = 8; height = 6
        properties = {
          title  = "ElastiCache — Connections"
          view   = "timeSeries"
          region = var.region
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/ElastiCache", "CurrConnections",
              "CacheClusterId", "${var.project}-redis-0001",
              { label = "Connections" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      }
    ]
  })
}

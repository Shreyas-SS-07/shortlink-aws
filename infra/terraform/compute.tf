data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.project}-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }
}

# HTTP listener: forward traffic when HTTPS is off; redirect to HTTPS when on.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.enable_https ? [] : [1]
      content {
        target_group {
          arn = aws_lb_target_group.app.arn
        }
      }
    }
  }
}

# HTTPS listener: only created when enable_https = true and cert is validated.
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.main[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile { name = aws_iam_instance_profile.app.name }
  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # containers can still reach IMDS for role creds
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    region        = var.region
    ecr_registry  = split("/", aws_ecr_repository.app.repository_url)[0]
    image         = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
    db_host       = aws_db_instance.main.address
    redis_host    = aws_elasticache_replication_group.main.primary_endpoint_address
    alb_dns       = aws_lb.main.dns_name
  }))

  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project}-asg"
  min_size                  = var.asg_min
  max_size                  = var.asg_max
  desired_capacity          = var.asg_min
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }
}

# Scale out when average CPU across the fleet passes 50%.
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.project}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

# Application Load Balancer for routing external traffic to worker nodes
# This is separate from the API server load balancer

# Network Load Balancer for application traffic
resource "aws_lb" "app" {
  name               = "${var.project_name}-${var.environment}-app-nlb"
  internal           = false  # External-facing
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-nlb"
    Environment = var.environment
    Purpose     = "application-traffic"
  }
}

resource "aws_lb_target_group" "http" {
  name     = "${var.project_name}-${var.environment}-http"
  port     = var.http_nodeport
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.http_nodeport
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-http-tg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "https" {
  name     = "${var.project_name}-${var.environment}-https"
  port     = var.https_nodeport
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.https_nodeport
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-https-tg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

# Attach worker nodes to HTTP target group
resource "aws_lb_target_group_attachment" "http" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.http.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = var.http_nodeport
}

# Attach worker nodes to HTTPS target group
resource "aws_lb_target_group_attachment" "https" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.https.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = var.https_nodeport
}

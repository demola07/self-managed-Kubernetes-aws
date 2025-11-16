# Module for adding additional services to the existing NLB
# Use this to expose services like ArgoCD, Grafana, etc. via the NLB

# Target Group for the service
resource "aws_lb_target_group" "service" {
  name     = "${var.project_name}-${var.environment}-${var.service_name}"
  port     = var.nodeport
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = var.nodeport
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    interval            = var.health_check_interval
  }

  deregistration_delay = var.deregistration_delay

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.service_name}-tg"
    Environment = var.environment
    Service     = var.service_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Attach worker nodes to target group
resource "aws_lb_target_group_attachment" "service" {
  count            = length(var.worker_instance_ids)
  target_group_arn = aws_lb_target_group.service.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = var.nodeport
}

# NLB Listener for the service
resource "aws_lb_listener" "service" {
  load_balancer_arn = var.load_balancer_arn
  port              = var.listener_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service.arn
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.service_name}-listener"
    Environment = var.environment
    Service     = var.service_name
  }
}

# Security Group Rule for NodePort
resource "aws_vpc_security_group_ingress_rule" "service_nodeport" {
  security_group_id = var.worker_security_group_id
  description       = "${var.service_name} NodePort for NLB"
  
  from_port   = var.nodeport
  to_port     = var.nodeport
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.service.arn
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.service.name
}

output "listener_arn" {
  description = "ARN of the NLB listener"
  value       = aws_lb_listener.service.arn
}

output "listener_port" {
  description = "Port the listener is listening on"
  value       = aws_lb_listener.service.port
}

output "nodeport" {
  description = "NodePort the service is exposed on"
  value       = var.nodeport
}

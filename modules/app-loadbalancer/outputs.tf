output "load_balancer_dns" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.app.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the application load balancer"
  value       = aws_lb.app.arn
}

output "load_balancer_zone_id" {
  description = "Zone ID of the application load balancer (for Route53)"
  value       = aws_lb.app.zone_id
}

output "http_target_group_arn" {
  description = "ARN of the HTTP target group"
  value       = aws_lb_target_group.http.arn
}

output "https_target_group_arn" {
  description = "ARN of the HTTPS target group"
  value       = aws_lb_target_group.https.arn
}

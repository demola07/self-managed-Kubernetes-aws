output "instance_ids" {
  description = "Control plane instance IDs"
  value       = aws_instance.control_plane[*].id
}

output "private_ips" {
  description = "Control plane private IPs"
  value       = aws_instance.control_plane[*].private_ip
}

output "api_server_lb_dns" {
  description = "API server load balancer DNS name"
  value       = aws_lb.api_server.dns_name
}

output "api_server_lb_arn" {
  description = "API server load balancer ARN"
  value       = aws_lb.api_server.arn
}

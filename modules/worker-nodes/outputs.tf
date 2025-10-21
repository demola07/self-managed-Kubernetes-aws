output "instance_ids" {
  description = "Worker node instance IDs"
  value       = aws_instance.worker[*].id
}

output "private_ips" {
  description = "Worker node private IPs"
  value       = aws_instance.worker[*].private_ip
}

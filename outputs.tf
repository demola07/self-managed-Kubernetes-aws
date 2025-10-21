output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = module.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Bastion host instance ID"
  value       = module.bastion.instance_id
}

output "control_plane_private_ips" {
  description = "Control plane nodes private IPs"
  value       = module.control_plane.private_ips
}

output "control_plane_instance_ids" {
  description = "Control plane instance IDs"
  value       = module.control_plane.instance_ids
}

output "worker_private_ips" {
  description = "Worker nodes private IPs"
  value       = module.worker_nodes.private_ips
}

output "worker_instance_ids" {
  description = "Worker instance IDs"
  value       = module.worker_nodes.instance_ids
}

output "ssh_bastion_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.bastion.public_ip}"
}

output "ssm_bastion_command" {
  description = "AWS SSM command to connect to bastion"
  value       = "aws ssm start-session --target ${module.bastion.instance_id}"
}

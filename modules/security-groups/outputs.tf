output "bastion_sg_id" {
  description = "Bastion security group ID"
  value       = aws_security_group.bastion.id
}

output "control_plane_sg_id" {
  description = "Control plane security group ID"
  value       = aws_security_group.control_plane.id
}

output "etcd_sg_id" {
  description = "etcd security group ID"
  value       = aws_security_group.etcd.id
}

output "worker_sg_id" {
  description = "Worker nodes security group ID"
  value       = aws_security_group.worker.id
}

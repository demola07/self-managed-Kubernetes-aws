output "bastion_instance_profile_name" {
  description = "Bastion instance profile name"
  value       = var.enable_ssm ? aws_iam_instance_profile.bastion[0].name : null
}

output "control_plane_instance_profile_name" {
  description = "Control plane instance profile name"
  value       = aws_iam_instance_profile.control_plane.name
}

output "worker_instance_profile_name" {
  description = "Worker instance profile name"
  value       = aws_iam_instance_profile.worker.name
}

output "bastion_role_arn" {
  description = "Bastion IAM role ARN"
  value       = var.enable_ssm ? aws_iam_role.bastion[0].arn : null
}

output "control_plane_role_arn" {
  description = "Control plane IAM role ARN"
  value       = aws_iam_role.control_plane.arn
}

output "worker_role_arn" {
  description = "Worker IAM role ARN"
  value       = aws_iam_role.worker.arn
}

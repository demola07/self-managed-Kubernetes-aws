variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "enable_ssm" {
  description = "Enable SSM for bastion host"
  type        = bool
  default     = true
}

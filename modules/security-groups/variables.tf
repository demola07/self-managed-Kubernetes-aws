variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
}

variable "gateway_http_nodeport" {
  description = "NodePort for Gateway API HTTP traffic"
  type        = number
  default     = 30080
}

variable "gateway_https_nodeport" {
  description = "NodePort for Gateway API HTTPS traffic"
  type        = number
  default     = 30443
}

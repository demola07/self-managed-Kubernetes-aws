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

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the load balancer"
  type        = list(string)
}

variable "worker_instance_ids" {
  description = "List of worker node instance IDs to attach to target groups"
  type        = list(string)
}

variable "http_nodeport" {
  description = "NodePort for HTTP traffic (Gateway API)"
  type        = number
  default     = 30080
}

variable "https_nodeport" {
  description = "NodePort for HTTPS traffic (Gateway API)"
  type        = number
  default     = 30443
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the load balancer"
  type        = bool
  default     = false
}

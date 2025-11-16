variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_name" {
  description = "Name of the service (e.g., argocd, grafana)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "load_balancer_arn" {
  description = "ARN of the existing NLB"
  type        = string
}

variable "worker_instance_ids" {
  description = "List of worker node instance IDs"
  type        = list(string)
}

variable "worker_security_group_id" {
  description = "Security group ID of worker nodes"
  type        = string
}

variable "nodeport" {
  description = "Kubernetes NodePort for the service"
  type        = number
}

variable "listener_port" {
  description = "NLB listener port (external port)"
  type        = number
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive health checks successes required"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive health check failures required"
  type        = number
  default     = 2
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
}

variable "deregistration_delay" {
  description = "Time to wait before deregistering a target"
  type        = number
  default     = 30
}

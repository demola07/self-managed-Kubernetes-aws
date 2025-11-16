variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "k8s-cluster"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# Bastion Configuration
variable "bastion_instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "bastion_enable_ssm" {
  description = "Enable AWS Systems Manager Session Manager for bastion"
  type        = bool
  default     = true
}

# Control Plane Configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.control_plane_count >= 1 && var.control_plane_count % 2 == 1
    error_message = "Control plane count must be an odd number (1, 3, 5, etc.) for etcd quorum."
  }
}

variable "control_plane_instance_type" {
  description = "Instance type for control plane nodes"
  type        = string
  default     = "t3.medium"
}

variable "control_plane_root_volume_size" {
  description = "Root volume size for control plane nodes (GB)"
  type        = number
  default     = 50
}

# Worker Node Configuration
variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.worker_node_count >= 1
    error_message = "Worker node count must be at least 1."
  }
}

variable "worker_instance_type" {
  description = "Instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "worker_root_volume_size" {
  description = "Root volume size for worker nodes (GB)"
  type        = number
  default     = 50
}

# SSH Configuration
variable "key_name" {
  description = "SSH key pair name for EC2 instances"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Gateway API / Load Balancer Configuration
variable "gateway_http_nodeport" {
  description = "NodePort for Gateway API HTTP traffic (must match Cilium Gateway service)"
  type        = number
  default     = 30080
}

variable "gateway_https_nodeport" {
  description = "NodePort for Gateway API HTTPS traffic (must match Cilium Gateway service)"
  type        = number
  default     = 30443
}

# ArgoCD NLB Configuration
variable "enable_argocd_nlb" {
  description = "Enable ArgoCD access via NLB"
  type        = bool
  default     = false
}

variable "argocd_nodeport" {
  description = "Kubernetes NodePort for ArgoCD service"
  type        = number
  default     = 30100
}

variable "argocd_listener_port" {
  description = "External port on NLB for ArgoCD access"
  type        = number
  default     = 8080
}

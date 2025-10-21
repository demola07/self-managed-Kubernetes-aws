terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr

  allowed_ssh_cidrs = var.allowed_ssh_cidrs
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  enable_ssm   = var.bastion_enable_ssm
}

# Bastion Host Module
module "bastion" {
  source = "./modules/bastion"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security_groups.bastion_sg_id]

  instance_type        = var.bastion_instance_type
  key_name             = var.key_name
  enable_ssm           = var.bastion_enable_ssm
  iam_instance_profile = var.bastion_enable_ssm ? module.iam.bastion_instance_profile_name : null
}

# Control Plane Nodes Module
module "control_plane" {
  source = "./modules/control-plane"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnet_ids
  security_group_ids = [
    module.security_groups.control_plane_sg_id,
    module.security_groups.etcd_sg_id
  ]

  node_count           = var.control_plane_count
  instance_type        = var.control_plane_instance_type
  key_name             = var.key_name
  iam_instance_profile = module.iam.control_plane_instance_profile_name
  root_volume_size     = var.control_plane_root_volume_size
}

# Worker Nodes Module
module "worker_nodes" {
  source = "./modules/worker-nodes"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.worker_sg_id]

  node_count           = var.worker_node_count
  instance_type        = var.worker_instance_type
  key_name             = var.key_name
  iam_instance_profile = module.iam.worker_instance_profile_name
  root_volume_size     = var.worker_root_volume_size
}

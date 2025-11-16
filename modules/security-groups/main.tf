# Bastion Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.environment}-bastion-"
  description = "Security group for bastion host"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from allowed CIDRs"
  
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_ssh_cidrs[0]
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound traffic"
  
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# Control Plane Security Group
resource "aws_security_group" "control_plane" {
  name_prefix = "${var.project_name}-${var.environment}-control-plane-"
  description = "Security group for Kubernetes control plane"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-control-plane-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Server (6443)
resource "aws_vpc_security_group_ingress_rule" "control_plane_api_server" {
  security_group_id = aws_security_group.control_plane.id
  description       = "Kubernetes API server"
  
  from_port   = 6443
  to_port     = 6443
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc_cidr
}

# API Server from bastion
resource "aws_vpc_security_group_ingress_rule" "control_plane_api_server_bastion" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Kubernetes API server from bastion"
  
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

# Kubelet API (10250)
resource "aws_vpc_security_group_ingress_rule" "control_plane_kubelet" {
  security_group_id = aws_security_group.control_plane.id
  description       = "Kubelet API"
  
  from_port   = 10250
  to_port     = 10250
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc_cidr
}

# kube-scheduler (10259)
resource "aws_vpc_security_group_ingress_rule" "control_plane_scheduler" {
  security_group_id = aws_security_group.control_plane.id
  description       = "kube-scheduler"
  
  from_port   = 10259
  to_port     = 10259
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc_cidr
}

# kube-controller-manager (10257)
resource "aws_vpc_security_group_ingress_rule" "control_plane_controller_manager" {
  security_group_id = aws_security_group.control_plane.id
  description       = "kube-controller-manager"
  
  from_port   = 10257
  to_port     = 10257
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc_cidr
}

# Cilium VXLAN (8472 UDP) for CNI overlay network
resource "aws_vpc_security_group_ingress_rule" "control_plane_cilium_vxlan" {
  security_group_id = aws_security_group.control_plane.id
  description       = "Cilium VXLAN overlay network"
  
  from_port   = 8472
  to_port     = 8472
  ip_protocol = "udp"
  cidr_ipv4   = var.vpc_cidr
}

# SSH from bastion
resource "aws_vpc_security_group_ingress_rule" "control_plane_ssh" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "SSH from bastion"
  
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

# Allow all traffic between control plane nodes
resource "aws_vpc_security_group_ingress_rule" "control_plane_self" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Allow all traffic between control plane nodes"
  
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id
}

resource "aws_vpc_security_group_egress_rule" "control_plane_all" {
  security_group_id = aws_security_group.control_plane.id
  description       = "Allow all outbound traffic"
  
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# etcd Security Group
resource "aws_security_group" "etcd" {
  name_prefix = "${var.project_name}-${var.environment}-etcd-"
  description = "Security group for etcd cluster"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-etcd-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# etcd client API (2379)
resource "aws_vpc_security_group_ingress_rule" "etcd_client" {
  security_group_id            = aws_security_group.etcd.id
  description                  = "etcd client API"
  
  from_port                    = 2379
  to_port                      = 2379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.control_plane.id
}

# etcd peer API (2380)
resource "aws_vpc_security_group_ingress_rule" "etcd_peer" {
  security_group_id            = aws_security_group.etcd.id
  description                  = "etcd peer API"
  
  from_port                    = 2380
  to_port                      = 2380
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.etcd.id
}

# Allow all traffic between etcd nodes
resource "aws_vpc_security_group_ingress_rule" "etcd_self" {
  security_group_id            = aws_security_group.etcd.id
  description                  = "Allow all traffic between etcd nodes"
  
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.etcd.id
}

resource "aws_vpc_security_group_egress_rule" "etcd_all" {
  security_group_id = aws_security_group.etcd.id
  description       = "Allow all outbound traffic"
  
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# Worker Nodes Security Group
resource "aws_security_group" "worker" {
  name_prefix = "${var.project_name}-${var.environment}-worker-"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-worker-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Kubelet API (10250)
resource "aws_vpc_security_group_ingress_rule" "worker_kubelet" {
  security_group_id            = aws_security_group.worker.id
  description                  = "Kubelet API from control plane"
  
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.control_plane.id
}

# NodePort Services (30000-32767) from VPC
resource "aws_vpc_security_group_ingress_rule" "worker_nodeport" {
  security_group_id = aws_security_group.worker.id
  description       = "NodePort Services from VPC"
  
  from_port   = 30000
  to_port     = 32767
  ip_protocol = "tcp"
  cidr_ipv4   = var.vpc_cidr
}

# HTTP NodePort for Gateway API from internet
resource "aws_vpc_security_group_ingress_rule" "worker_http_nodeport" {
  security_group_id = aws_security_group.worker.id
  description       = "HTTP NodePort for Gateway API (from NLB)"
  
  from_port   = var.gateway_http_nodeport
  to_port     = var.gateway_http_nodeport
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

# HTTPS NodePort for Gateway API from internet
resource "aws_vpc_security_group_ingress_rule" "worker_https_nodeport" {
  security_group_id = aws_security_group.worker.id
  description       = "HTTPS NodePort for Gateway API (from NLB)"
  
  from_port   = var.gateway_https_nodeport
  to_port     = var.gateway_https_nodeport
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

# Cilium VXLAN (8472 UDP) for CNI overlay network
resource "aws_vpc_security_group_ingress_rule" "worker_cilium_vxlan" {
  security_group_id = aws_security_group.worker.id
  description       = "Cilium VXLAN overlay network"
  
  from_port   = 8472
  to_port     = 8472
  ip_protocol = "udp"
  cidr_ipv4   = var.vpc_cidr
}

# SSH from bastion
resource "aws_vpc_security_group_ingress_rule" "worker_ssh" {
  security_group_id            = aws_security_group.worker.id
  description                  = "SSH from bastion"
  
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

# Allow all traffic between worker nodes
resource "aws_vpc_security_group_ingress_rule" "worker_self" {
  security_group_id            = aws_security_group.worker.id
  description                  = "Allow all traffic between worker nodes"
  
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id
}

# Allow traffic from control plane
resource "aws_vpc_security_group_ingress_rule" "worker_from_control_plane" {
  security_group_id            = aws_security_group.worker.id
  description                  = "Allow traffic from control plane"
  
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id
}

# Allow traffic to control plane
resource "aws_vpc_security_group_ingress_rule" "control_plane_from_worker" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Allow traffic from worker nodes"
  
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id
}

resource "aws_vpc_security_group_egress_rule" "worker_all" {
  security_group_id = aws_security_group.worker.id
  description       = "Allow all outbound traffic"
  
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

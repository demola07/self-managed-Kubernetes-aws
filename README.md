# Self-Managed Kubernetes on AWS

Production-ready infrastructure for deploying a self-managed Kubernetes cluster on AWS using **Terraform**, **kubeadm**, **containerd**, and **Cilium CNI**. Features high availability, security best practices, and full AWS integration.

## 🎯 Features

- ✅ **High Availability**: Multi-AZ deployment with internal NLB for API server
- ✅ **Security**: Private subnets, bastion host, encrypted volumes, IMDSv2
- ✅ **Production Ready**: Kubernetes 1.33.x with containerd runtime
- ✅ **CNI**: Cilium (eBPF-based) for high-performance networking  
- ✅ **AWS Integration**: IAM roles for EBS, ELB, ECR, and autoscaling
- ✅ **Flexible**: Configurable node counts, instance types, and regions
- ✅ **Documentation**: Comprehensive setup and operations guides

## 📋 Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Infrastructure Components](#infrastructure-components)
- [Configuration](#configuration)
- [Kubernetes Setup](#kubernetes-setup)
- [Security](#security)
- [Monitoring & Operations](#monitoring--operations)
- [Troubleshooting](#troubleshooting)
- [Cost Optimization](#cost-optimization)

## 🏗️ Architecture

### Network Design

```
                    Internet Gateway
                           |
                  Public Subnets (Multi-AZ)
                    |              |
                Bastion         NAT Gateways
                    |              |
                  Private Subnets (Multi-AZ)
                           |
        ┌──────────────────┼──────────────────┐
        |                  |                  |
   Control Plane      Workers (3+)      Internal NLB
   Nodes (3+)                           (API Server HA)
```

### Components

| Component | Count | Location | Purpose |
|-----------|-------|----------|---------|
| **VPC** | 1 | Multi-AZ | Network isolation |
| **Control Plane** | 2+ | Private subnets | Kubernetes control plane |
| **Worker Nodes** | 1+ | Private subnets | Application workloads |
| **Bastion** | 1 | Public subnet | Secure access point |
| **NLB** | 1 | Private subnets | API server HA |
| **NAT Gateways** | 2+ | Public subnets | Outbound internet |

### Security Groups

- **Bastion**: SSH (22) from allowed CIDRs
- **Control Plane**: API (6443), Kubelet (10250), Scheduler (10259), Controller Manager (10257)
- **Workers**: Kubelet (10250), NodePort (30000-32767)
- **Cilium**: VXLAN (8472 UDP)

## 📦 Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.5.0
3. **AWS CLI** configured with credentials
4. **SSH Key Pair** created in AWS
5. **kubectl** (for cluster management)
6. **Helm** (for Cilium installation)

## 🚀 Quick Start

See [QUICKSTART.md](QUICKSTART.md) for detailed setup guide.

### 1. Clone and Configure

```bash
git clone <repository-url>
cd self-managed-kubernetes
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit Configuration

```hcl
# terraform.tfvars
aws_region          = "us-east-1"
project_name        = "k8s-cluster"
environment         = "dev"
key_name            = "your-aws-key-pair"
allowed_ssh_cidrs   = ["YOUR_IP/32"]

control_plane_count = 2
worker_node_count   = 2
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform apply
```

**Wait**: ~10-15 minutes for deployment

### 4. Initialize Kubernetes

```bash
# SSH to bastion
ssh -A -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw bastion_public_ip)

# SSH to first control plane
ssh ubuntu@<control-plane-ip>

# Initialize cluster
API_LB=$(terraform output -raw api_server_lb_dns)
sudo kubeadm init \
  --control-plane-endpoint="${API_LB}:6443" \
  --upload-certs \
  --pod-network-cidr=10.217.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 5. Install Cilium CNI

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Cilium
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.14.5 \
  --namespace kube-system \
  --set kubeProxyReplacement=false \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=kubernetes \
  --set k8sServiceHost=${API_LB} \
  --set k8sServicePort=6443
```

### 6. Join Additional Nodes

Use the join commands from step 4 output.

**Control Plane Nodes**:
```bash
sudo kubeadm join ${API_LB}:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <key> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

**Worker Nodes**:
```bash
sudo kubeadm join ${API_LB}:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

### 7. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## 🏢 Infrastructure Components

### VPC Module

- **CIDR**: 10.0.0.0/16 (configurable)
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24 (Multi-AZ)
- **Private Subnets**: 10.0.11.0/24, 10.0.12.0/24 (Multi-AZ)
- **NAT Gateways**: One per AZ for high availability
- **VPC Flow Logs**: Enabled for network monitoring

### IAM Roles

#### Control Plane Role
- EC2 describe/create/modify (volumes, security groups, routes)
- ELB create/manage (for LoadBalancer services)
- ECR read (pull container images)
- AutoScaling describe/modify (for cluster autoscaler)
- SSM managed instance core

#### Worker Role
- EC2 describe (read-only)
- ECR read (pull container images)
- SSM managed instance core

#### Bastion Role
- SSM managed instance core

### Security Groups

All security groups follow the principle of least privilege with explicit allow rules.

**Control Plane**:
- API Server (6443): From VPC CIDR + Bastion
- Kubelet (10250): From VPC CIDR
- Scheduler (10259): From VPC CIDR
- Controller Manager (10257): From VPC CIDR
- SSH (22): From Bastion only
- All traffic: Between control plane nodes

**Workers**:
- Kubelet (10250): From Control Plane
- NodePort (30000-32767): From VPC CIDR
- SSH (22): From Bastion only
- All traffic: Between worker nodes and from control plane

**Cilium**:
- VXLAN (8472 UDP): Between all cluster nodes

## ⚙️ Configuration

### Node Scaling

```hcl
# terraform.tfvars
control_plane_count = 3  # Odd numbers recommended (1, 3, 5)
worker_node_count   = 5  # Any number >= 1
```

### Instance Types

```hcl
control_plane_instance_type = "t3.large"
worker_instance_type        = "t3.xlarge"
bastion_instance_type       = "t3.micro"
```

### Storage

```hcl
control_plane_root_volume_size = 50  # GB
worker_root_volume_size        = 50  # GB
```

### Network

```hcl
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
```

## 🔐 Security

### Network Security

- **Private Subnets**: All cluster nodes in private subnets with no direct internet access
- **Bastion Host**: Single entry point with SSH key authentication
- **Security Groups**: Least privilege with explicit port rules
- **VPC Flow Logs**: Network traffic monitoring enabled
- **Encrypted Volumes**: All EBS volumes encrypted at rest
- **IMDSv2**: Metadata service requires session tokens

### Access Control

**SSH Access**:
```bash
# Via bastion with agent forwarding
ssh -A -i ~/.ssh/key.pem ubuntu@<bastion-ip>
ssh ubuntu@<node-private-ip>
```

**SSM Access** (if enabled):
```bash
aws ssm start-session --target <instance-id>
```

### IAM Best Practices

- Separate roles for control plane, workers, and bastion
- Minimal required permissions (least privilege)
- No hardcoded credentials
- Instance profiles for AWS service access

### Kubernetes Security

- **RBAC**: Role-based access control enabled
- **Network Policies**: Supported via Cilium
- **Pod Security**: Configure pod security standards
- **Secrets**: Use external secrets operator for sensitive data
- **Audit Logging**: Enable API server audit logs

## 📊 Monitoring & Operations

### Recommended Tools

- **Metrics Server**: Resource metrics (`kubectl top`)
- **Prometheus + Grafana**: Metrics and dashboards
- **Cilium Hubble**: Network observability
- **EFK Stack**: Centralized logging
- **AlertManager**: Alerting

### Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for self-managed clusters
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP"}
]'
```

### Maintenance Operations

**Add Nodes**:
1. Update `terraform.tfvars` with new count
2. Run `terraform apply`
3. Join new nodes using kubeadm

**Remove Nodes**:
1. Drain node: `kubectl drain <node> --ignore-daemonsets`
2. Delete node: `kubectl delete node <node>`
3. Update `terraform.tfvars` and apply

**Upgrade Kubernetes**:
- Follow official kubeadm upgrade guide
- Test in staging environment first
- Upgrade control plane nodes first, then workers

## 🔧 Troubleshooting

### Cannot SSH to Bastion

- Check `allowed_ssh_cidrs` in terraform.tfvars
- Verify security group allows your IP
- Ensure correct SSH key pair

### Nodes Not Joining Cluster

- Check security group rules (ports 6443, 10250)
- Verify network connectivity between nodes
- Check kubelet logs: `journalctl -xeu kubelet`
- Ensure containerd is running: `systemctl status containerd`

### API Server Unreachable

- Verify NLB health checks are passing
- Check control plane node status
- Review security group rules for port 6443
- Check API server logs: `kubectl logs -n kube-system kube-apiserver-<node>`

### Pods Not Starting

- Check CNI installation: `kubectl get pods -n kube-system -l k8s-app=cilium`
- Verify pod CIDR matches kubeadm init: `10.217.0.0/16`
- Check node status: `kubectl describe node <node>`

### Common Commands

```bash
# View cluster info
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Check component status
kubectl get componentstatuses

# View logs
journalctl -u kubelet -f
kubectl logs -n kube-system <pod>

# Debug networking
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
```

## 💰 Cost Optimization

### Estimated Monthly Costs (us-east-1)

| Resource | Quantity | Cost/Month |
|----------|----------|------------|
| t3.medium control plane | 2 | ~$60 |
| t3.medium workers | 2 | ~$60 |
| t3.micro bastion | 1 | ~$7 |
| NAT Gateways | 2 | ~$65 |
| Network Load Balancer | 1 | ~$20 |
| EBS volumes (200GB) | - | ~$20 |
| **Total** | - | **~$232/month** |

### Cost Reduction Strategies

1. **Right-size instances**: Monitor utilization and adjust
2. **Single NAT Gateway**: Use one NAT (not HA) for dev/test
3. **Reserved Instances**: Purchase for stable workloads
4. **Spot Instances**: Use for non-critical workers
5. **Stop when not in use**: Shut down dev/test clusters
6. **Cluster Autoscaler**: Scale workers based on demand

## 📚 Additional Resources

### Documentation

- **Setup Guides**: See `k8s-setup/` directory
  - `ubuntu-cilium-setup.md`: Ubuntu + Cilium specific guide
  - `self-managed-k8s-cluster-instructions.md`: OS-agnostic guide
  - `metrics-server-setup.md`: Metrics server installation
- **Manual Setup**: `manual-aws-setup.md` for AWS Console setup
- **Quick Start**: `QUICKSTART.md` for rapid deployment

### Project Structure

```
.
├── main.tf                          # Root module
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── terraform.tfvars.example         # Example configuration
├── README.md                        # This file
├── QUICKSTART.md                    # Quick start guide
├── manual-aws-setup.md              # Manual AWS setup guide
├── k8s-setup/                       # Kubernetes setup guides
│   ├── ubuntu-cilium-setup.md
│   ├── self-managed-k8s-cluster-instructions.md
│   └── metrics-server-setup.md
└── modules/
    ├── vpc/                         # VPC infrastructure
    ├── security-groups/             # Security groups
    ├── iam/                         # IAM roles and policies
    ├── bastion/                     # Bastion host
    ├── control-plane/               # Control plane nodes + NLB
    └── worker-nodes/                # Worker nodes
```

### Outputs

After deployment, get useful information:

```bash
terraform output                      # All outputs
terraform output bastion_public_ip    # Bastion IP
terraform output api_server_lb_dns    # API LB DNS
terraform output control_plane_private_ips  # Control plane IPs
terraform output worker_private_ips   # Worker IPs
```

## 🤝 Contributing

Contributions welcome! Please ensure:
- Code follows Terraform best practices
- Security considerations are maintained
- Documentation is updated
- Changes are tested

## 📄 License

MIT License - Free to use and modify

## 🙏 Acknowledgments

- Kubernetes community for excellent documentation
- Cilium project for eBPF-based networking
- HashiCorp for Terraform
- AWS for cloud infrastructure

---

**Author**: Ademola Sobaki

**Repository**: Production-ready self-managed Kubernetes on AWS

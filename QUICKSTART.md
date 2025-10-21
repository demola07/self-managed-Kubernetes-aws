# ⚡ Quick Start Guide

Get your Kubernetes cluster running in 15 minutes!

## Prerequisites

- ✅ AWS account with appropriate permissions
- ✅ Terraform >= 1.5.0 installed
- ✅ AWS CLI configured (`aws configure`)
- ✅ SSH key pair created in AWS
- ✅ Your public IP address

## 🚀 5-Step Deployment

### Step 1: Configure (2 minutes)

```bash
# Clone repository
git clone <repository-url>
cd self-managed-kubernetes

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region        = "us-east-1"
project_name      = "k8s-cluster"
environment       = "dev"

# IMPORTANT: Update these
key_name          = "your-aws-key-pair-name"
allowed_ssh_cidrs = ["YOUR_IP/32"]  # Get your IP: curl ifconfig.me

# Node configuration
control_plane_count = 2
worker_node_count   = 2

# Optional: Enable SSM for keyless access
bastion_enable_ssm = true
```

### Step 2: Deploy Infrastructure (10-15 minutes)

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy (auto-approve to skip confirmation)
terraform apply -auto-approve
```

**☕ Take a break**: Infrastructure deployment takes ~10-15 minutes

### Step 3: Access Bastion (1 minute)

```bash
# Get bastion IP
BASTION_IP=$(terraform output -raw bastion_public_ip)

# SSH to bastion with agent forwarding
ssh -A -i ~/.ssh/your-key.pem ubuntu@${BASTION_IP}
```

**Alternative - SSM** (if enabled):
```bash
aws ssm start-session --target $(terraform output -raw bastion_instance_id)
```

### Step 4: Initialize Kubernetes (5 minutes)

From bastion, SSH to first control plane node:

```bash
# Get control plane IPs
terraform output control_plane_private_ips

# SSH to first control plane (from bastion)
ssh ubuntu@<first-control-plane-ip>
```

Initialize the cluster:

```bash
# Get API Load Balancer DNS
API_LB="<your-api-lb-dns>"  # From terraform output api_server_lb_dns

# Initialize cluster
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

**💾 Save the join commands** from the output!

### Step 5: Install Cilium CNI (2 minutes)

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add Cilium repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium
helm install cilium cilium/cilium \
  --version 1.14.5 \
  --namespace kube-system \
  --set kubeProxyReplacement=false \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=kubernetes \
  --set k8sServiceHost=${API_LB} \
  --set k8sServicePort=6443

# Verify installation
kubectl get pods -n kube-system -l k8s-app=cilium
```

## 🎯 Join Additional Nodes

### Join Second Control Plane Node

SSH to second control plane node and run:

```bash
sudo kubeadm join ${API_LB}:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

### Join Worker Nodes

SSH to each worker node and run:

```bash
sudo kubeadm join ${API_LB}:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

**Lost join commands?** Regenerate them:
```bash
kubeadm token create --print-join-command
```

## ✅ Verify Cluster

```bash
# Check nodes
kubectl get nodes

# Expected output:
# NAME                              STATUS   ROLES           AGE   VERSION
# k8s-cluster-dev-control-plane-1   Ready    control-plane   5m    v1.33.x
# k8s-cluster-dev-control-plane-2   Ready    control-plane   3m    v1.33.x
# k8s-cluster-dev-worker-1          Ready    <none>          2m    v1.33.x
# k8s-cluster-dev-worker-2          Ready    <none>          2m    v1.33.x

# Check all pods
kubectl get pods -A

# Check Cilium status
kubectl get pods -n kube-system -l k8s-app=cilium
```

## 🎨 Optional: Install Cilium CLI

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# Check status
cilium status

# Run connectivity test (optional)
cilium connectivity test
```

## 📊 Install Metrics Server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for self-managed clusters
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP"}
]'

# Wait for metrics to be available (1-2 minutes)
kubectl top nodes
```

## 🧪 Test Your Cluster

Deploy a sample application:

```bash
# Create deployment
kubectl create deployment nginx --image=nginx --replicas=3

# Expose as NodePort service
kubectl expose deployment nginx --port=80 --type=NodePort

# Check status
kubectl get pods
kubectl get svc nginx

# Test from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://nginx
```

## 🔄 Access kubectl from Bastion

Copy kubeconfig from control plane to bastion:

```bash
# On bastion
mkdir -p ~/.kube
scp ubuntu@<control-plane-ip>:~/.kube/config ~/.kube/config

# Update server endpoint to use LB
API_LB="<your-api-lb-dns>"
sed -i "s|server: https://.*:6443|server: https://${API_LB}:6443|g" ~/.kube/config

# Test
kubectl get nodes
```

## 🧹 Cleanup

To destroy all resources:

```bash
terraform destroy
```

**⚠️ Warning**: This deletes everything. Backup important data first!

## 📋 Useful Commands

```bash
# Show all outputs
terraform output

# Get specific output
terraform output bastion_public_ip
terraform output api_server_lb_dns

# SSH to bastion
ssh -A -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw bastion_public_ip)

# SSM to bastion
aws ssm start-session --target $(terraform output -raw bastion_instance_id)

# View infrastructure state
terraform show

# Format Terraform files
terraform fmt -recursive
```

## 🔧 Troubleshooting

### Cannot SSH to Bastion

```bash
# Check your IP
curl ifconfig.me

# Verify it matches allowed_ssh_cidrs in terraform.tfvars
# Update if needed and re-apply
terraform apply
```

### Nodes Not Ready

```bash
# Check kubelet logs
journalctl -xeu kubelet

# Check containerd
systemctl status containerd

# Check CNI pods
kubectl get pods -n kube-system -l k8s-app=cilium
```

### API Server Unreachable

```bash
# Check NLB health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Check API server logs
kubectl logs -n kube-system kube-apiserver-<node>

# Verify security groups allow port 6443
```

## 📚 Next Steps

1. **Configure kubectl locally**: Copy kubeconfig to your machine
2. **Install Ingress Controller**: nginx-ingress or AWS ALB Controller
3. **Set up monitoring**: Prometheus + Grafana
4. **Configure autoscaling**: Cluster Autoscaler or Karpenter
5. **Deploy applications**: Start with your workloads
6. **Set up CI/CD**: GitOps with ArgoCD or Flux

## 💰 Cost Estimate

**Default configuration** (2 control plane + 2 workers):

| Resource | Cost/Month |
|----------|------------|
| 2x t3.medium control plane | ~$60 |
| 2x t3.medium workers | ~$60 |
| 1x t3.micro bastion | ~$7 |
| 2x NAT Gateways | ~$65 |
| Network Load Balancer | ~$20 |
| EBS volumes | ~$20 |
| **Total** | **~$232/month** |

## 📖 Additional Documentation

- **README.md**: Complete documentation
- **k8s-setup/**: Detailed Kubernetes setup guides
- **manual-aws-setup.md**: Manual AWS Console setup
- **metrics-server-setup.md**: Metrics server guide

## 🆘 Support

- Check logs: `/var/log/user-data.log` on instances
- Kubernetes docs: https://kubernetes.io/docs/
- Cilium docs: https://docs.cilium.io/
- Terraform AWS docs: https://registry.terraform.io/providers/hashicorp/aws/

---

**Happy Clustering! 🎉**

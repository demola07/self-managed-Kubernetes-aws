# 🧱 Self-Managed Kubernetes on EC2 (kubeadm + containerd)

Production-focused, OS-agnostic installation guide. Default runtime: **containerd**. Flexible CNI: **Cilium / Calico / Flannel / others**.

## Overview

This document describes a production-oriented process to bootstrap a self-managed Kubernetes cluster on cloud VMs (AWS EC2) using **kubeadm**, **containerd**, and a pluggable CNI. It is intentionally OS-agnostic: commands are grouped by distribution where needed (Ubuntu/Debian, RHEL/CentOS/Alma, Amazon Linux).

### Assumptions & Goals

- Control plane nodes and worker nodes on private subnets with reliable networking
- Container runtime: **containerd** (default)
- CRI-agnostic instructions (notes for CRI-O / Docker included)
- Version pinning for kube components (recommend pinning in production)
- Minimal, repeatable steps suitable for automation

---

## Prerequisites

- **Linux VMs**: Ubuntu 22.04+, Debian 12+, RHEL/CentOS 8+, Amazon Linux 2+
- **Resources**: 2+ vCPUs, 4+ GB RAM for control plane (recommendation)
- **Time synchronized**: chrony or systemd-timesyncd
- **Network**: Inter-node connectivity on private subnet
- **Security groups / firewall**: Open for required ports (API server 6443, kubelet 10250, etc.)
- **Access**: SSH access and sudo privileges

### Required Ports

- **TCP 6443**: Kubernetes API server
- **TCP 2379-2380**: etcd (control plane only, if external etcd)
- **TCP 10250**: kubelet
- **UDP/TCP ranges**: For your chosen CNI (see CNI section)

---

## 1. System Preparation (All Nodes)

### 1.1 Update & Essential Packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
```

### 1.2 Disable Swap (Required)

```bash
sudo swapoff -a
# Comment out any swap lines in /etc/fstab
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### 1.3 Load Kernel Modules

Load `overlay` module (required by containerd):

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
EOF

sudo modprobe overlay
```

### 1.4 Configure Sysctl for Cilium

Cilium requires IP forwarding enabled:

```bash
cat <<EOF | sudo tee /etc/sysctl.d/99-k8s.conf
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

> **Note**: Cilium (eBPF-based) does not require `br_netfilter` or bridge netfilter sysctls.

---

## 2. Install and Configure Containerd

Containerd is the container runtime for this cluster.

### 2.1 Install Containerd

```bash
sudo apt-get update
sudo apt-get install -y containerd
```

### 2.2 Create Default Config and Enable Systemd Cgroups

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
# Optional: pin the pause image
sudo sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml
```

### 2.3 Start & Enable

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl status containerd --no-pager
```

### 2.4 Install CNI Plugins

```bash
sudo mkdir -p /opt/cni/bin
curl -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz | sudo tar -C /opt/cni/bin -xz
sudo mkdir -p /usr/lib/cni
sudo ln -s /opt/cni/bin/* /usr/lib/cni/ || true
```

### 2.5 Configure crictl for Debug (Optional)

```bash
sudo cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
```

---

## 3. Install kubeadm, kubelet, kubectl

Pin versions in production. Example below uses 1.33.x — replace with your vetted version.

### 3.1 Add Kubernetes Repository & Install

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
KUBE_VERSION="1.33.2-1.1"
sudo apt-get install -y kubelet=$KUBE_VERSION kubeadm=$KUBE_VERSION kubectl=$KUBE_VERSION
sudo apt-mark hold kubelet kubeadm kubectl
```

---

## 4. Cluster Initialization (Control Plane)

### 4.1 Initialize the Cluster

For Cilium, we use `10.217.0.0/16` as the Pod CIDR. Ensure this does not overlap with your VPC CIDR.

```bash
sudo kubeadm init \
  --pod-network-cidr=10.217.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

> **Note**: If using a load balancer for HA, add `--control-plane-endpoint` and `--apiserver-cert-extra-sans` flags.

### Configure kubectl for Admin

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## 5. Install Cilium CNI

Install Cilium using Helm after the control plane is ready.

### 5.1 Install Helm (if not already installed)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 5.2 Install Cilium

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.14.5 \
  --namespace kube-system \
  --set kubeProxyReplacement=false \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set ipam.mode=kubernetes \
  --set k8sServiceHost=$(hostname -I | awk '{print $1}') \
  --set k8sServicePort=6443
```

### 5.3 Install Cilium CLI (Optional but Recommended)

The Cilium CLI provides useful debugging and status commands:

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

### 5.4 Verify Cilium Installation

```bash
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Check nodes
kubectl get nodes -o wide

# Check Cilium status (if CLI installed)
cilium status

# Run connectivity test (optional)
cilium connectivity test
```

All nodes should show `Ready` status once Cilium pods are running.

---

## 6. Join Worker Nodes

On each worker node: repeat steps 1 → 3 (system prep, containerd, binaries). Then run the `kubeadm join` command produced at init or re-generate it:

```bash
kubeadm token create --print-join-command
```

Run the printed command on the worker nodes (may require sudo). Example:

```bash
sudo kubeadm join 10.0.1.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --cri-socket=unix:///run/containerd/containerd.sock
```

Verify from control plane:

```bash
kubectl get nodes
```

---

## 7. Useful Troubleshooting Commands

```bash
# View kubelet logs on node
journalctl -u kubelet -f

# Check pods and describe issues
kubectl get pods -A
kubectl describe pod <pod> -n <ns>

# Debug runtime
crictl ps -a
crictl logs <container-id>

# Token management
kubeadm token list
kubeadm token create --print-join-command
```

---

## 8. Resetting a Node / Reinitializing

To reset a node (careful on control plane):

```bash
sudo kubeadm reset --cri-socket=unix:///run/containerd/containerd.sock
sudo rm -rf /etc/kubernetes /var/lib/etcd $HOME/.kube
sudo systemctl restart containerd
```

---

## 9. Production Notes

- **Version management**: Always pin kubeadm, kubelet, and kubectl versions. Test upgrades in a staging environment before production.
- **Cilium features**: Consider enabling Hubble for observability and network policy enforcement.
- **Monitoring**: Deploy metrics-server, Prometheus, and Grafana for cluster monitoring.

---

## 10. Configuration Reference

- **OS**: Ubuntu 22.04+
- **Container Runtime**: containerd
- **CNI**: Cilium 1.14.5+
- **Pod CIDR**: `10.217.0.0/16`
- **containerd socket**: `unix:///run/containerd/containerd.sock`
- **Kubernetes version**: 1.33.x (adjust to your requirements)

---

**Author**: Ademola Sobaki — Ubuntu + Cilium Kubernetes Setup Guide

**End of document.**

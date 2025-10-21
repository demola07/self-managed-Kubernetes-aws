# 🧱 Self-Managed Kubernetes on EC2 (kubeadm + containerd)

Production-focused, OS-agnostic installation guide. Default runtime: **containerd**. Flexible CNI: **Cilium / Calico / Flannel / others**. This guide favors reproducibility and clarity.

## Overview

This document describes a production-oriented process to bootstrap a self-managed Kubernetes cluster on cloud VMs (AWS EC2) using **kubeadm**, **containerd**, and a pluggable CNI. It is intentionally OS-agnostic: commands are grouped by distribution where needed (Ubuntu/Debian, RHEL/CentOS/Alma, Amazon Linux).

### Assumptions & Goals

- Control plane nodes and worker nodes on private subnets with reliable networking
- Container runtime: **containerd** (default)
- CRI-agnostic instructions (notes for CRI-O / Docker included)
- Version pinning for kube components (recommend pinning in production)
- Minimal, repeatable steps suitable for automation

---

## 🧰 Prerequisites

- **Linux VMs**: Ubuntu 22.04+, Debian 12+, RHEL/CentOS 8+, Amazon Linux 2+
- **Resources**: 2+ vCPUs, 4+ GB RAM for control plane (recommendation)
- **Time sync**: chrony or systemd-timesyncd
- **Network**: Inter-node connectivity on private subnet
- **Security groups / firewall**: Open required ports (see below)
- **Access**: SSH access and sudo privileges

### Required Ports

- **TCP 6443**: Kubernetes API server
- **TCP 2379-2380**: etcd (control plane only, if external etcd)
- **TCP 10250**: kubelet
- **TCP 179**: Calico BGP (if using Calico)
- **UDP 8472**: VXLAN (if using Cilium)
- **UDP/TCP ranges**: For your chosen CNI (see CNI section)

---

## ⚙️ 1. System Preparation (All Nodes)

### 1.1 Update & Essential Packages

**Ubuntu / Debian:**

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
```

**RHEL / CentOS / AlmaLinux:**

```bash
sudo yum update -y
sudo yum install -y yum-utils device-mapper-persistent-data lvm2 curl ca-certificates
```

**Amazon Linux 2:**

```bash
sudo yum update -y
sudo yum install -y curl ca-certificates jq
```

### 1.2 Disable Swap (Required)

Kubernetes requires swap to be disabled.

```bash
sudo swapoff -a
# Comment out any swap lines in /etc/fstab
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### 1.3 Kernel Modules & Sysctl

Load `overlay` (required by container runtimes) and optionally `br_netfilter` (needed by some CNIs/iptables):

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter || true
```

### 1.4 Persist Network Sysctls

Persist network sysctls used by many CNIs:

```bash
cat <<EOF | sudo tee /etc/sysctl.d/99-k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

> **Note**: Cilium (eBPF-based) does not require `br_netfilter` for basic functionality, but having it enabled is safe and compatible with iptables-based CNIs.

---

## 🪪 2. Install and Configure Containerd (Default)

Containerd is the recommended CRI for production kubeadm clusters. If you prefer CRI-O, adapt commands to install `cri-o` and configure the CRI socket accordingly.

### 2.1 Install Containerd

**Ubuntu / Debian (package):**

```bash
sudo apt-get update
sudo apt-get install -y containerd
```

**RHEL/CentOS / Amazon Linux (package or binary):**

On RHEL/CentOS you can use the distribution packages or download a release tarball from the [containerd releases page](https://github.com/containerd/containerd/releases) and install the binary and service.

> **Note**: When installing manually, you must also install `runc`.

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

Kubernetes requires CNI binaries under `/opt/cni/bin`.

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

## 🧩 3. Install kubeadm, kubelet, kubectl

Pin versions in production. Example below uses 1.33.x as an example — replace with your vetted version.

### 3.1 Add Kubernetes Repo & Install (Ubuntu/Debian Example)

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
KUBE_VERSION="1.33.2-1.1"
sudo apt-get install -y kubelet=$KUBE_VERSION kubeadm=$KUBE_VERSION kubectl=$KUBE_VERSION
sudo apt-mark hold kubelet kubeadm kubectl
```

> **For RHEL/CentOS**, use the corresponding repository and `yum install` with version pins.

Verify installation:

```bash
kubeadm version
kubelet --version
kubectl version --client
```

---

## 🧠 4. Cluster Initialization (Control Plane)

This section explains **why** we use `--pod-network-cidr` and `--cri-socket` and how to run `kubeadm init`.

### Why `--pod-network-cidr`?

`--pod-network-cidr` defines the IP address range from which Pod IPs are allocated. Many CNIs require this CIDR at init time (or expect it to match their configuration). If the Pod CIDR overlaps with your VPC or host networks, routing breaks — choose a non-overlapping range.

**Examples:**
- **Calico** often uses: `192.168.0.0/16`
- **Flannel** frequently uses: `10.244.0.0/16`
- **Cilium** commonly uses: `10.217.0.0/16` (arbitrary example)

Pick a CIDR that does not overlap with your VPC. Record it and use the same value when installing the CNI (if required).

### Why `--cri-socket`?

`--cri-socket` tells kubeadm which container runtime socket to use (example for containerd: `unix:///run/containerd/containerd.sock`). Use it when:
- Multiple CRIs are present, or
- You want deterministic behavior in automation.

### Recommended kubeadm init (Example)

```bash
sudo kubeadm init \
  --pod-network-cidr=10.217.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

If you use an external Load Balancer for control plane HA, pass `--control-plane-endpoint` and `--apiserver-cert-extra-sans` / `--apiserver-advertise-address` as needed.

### Configure kubectl for Admin

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

(Optional: persist environment variable)

```bash
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

---

## 🌐 5. Install a CNI (Choose One)

Install a CNI after the control plane is Ready. The CNI you choose must be compatible with the pod CIDR you set in `kubeadm init` (or override the CNI to match your chosen CIDR).

### Option A — Cilium (eBPF, High Performance)

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

Cilium has advanced features (Hubble, eBPF tracing). It does not require `br_netfilter` strictly but works well with it enabled.

**Install Cilium CLI (Optional but Recommended):**

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

**Verify Cilium:**

```bash
cilium status
cilium connectivity test  # Optional connectivity test
```

### Option B — Calico (iptables/BGP, Stable)

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml
kubectl apply -f custom-resources.yaml
```

Calico commonly needs `br_netfilter` and appropriate sysctl settings.

### Option C — Flannel (Simple, Overlay)

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Verify CNI

```bash
kubectl get pods -n kube-system
kubectl get nodes -o wide
```

---

## ⚡ 6. Join Worker Nodes

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

## 🛠️ 7. Useful Troubleshooting Commands

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

## 🔁 8. Resetting a Node / Reinitializing

To reset a node (careful on control plane):

```bash
sudo kubeadm reset --cri-socket=unix:///run/containerd/containerd.sock
sudo rm -rf /etc/kubernetes /var/lib/etcd $HOME/.kube
sudo systemctl restart containerd
```

---

## 📝 9. Notes & CRI Alternatives

- **CRI-O**: If you prefer CRI-O, install it and use `--cri-socket=/var/run/crio/crio.sock` with kubeadm.S

---

## 📋 10. Appendix: Example Values & Decisions

- **Example Pod CIDR**: `10.217.0.0/16` (ensure no overlap with VPC)
- **containerd socket**: `unix:///run/containerd/containerd.sock`
- **Kubernetes component versions**: Pin to your organisation's supported versions (example: 1.33.x)

---

## ✅ Summary

You now have a production-ready, self-managed Kubernetes cluster on AWS EC2 with:

- ✅ **Containerd** as the container runtime (CRI-compliant)
- ✅ **kubeadm** for cluster bootstrapping
- ✅ **CNI plugin** (Cilium, Calico, or Flannel) for pod networking
- ✅ **OS-agnostic** approach supporting Ubuntu/Debian, RHEL/CentOS, Amazon Linux
- ✅ **Properly configured** control plane and worker nodes
- ✅ **Security best practices** (swap disabled, kernel modules, sysctl settings)
- ✅ **Version pinning** for reproducible deployments

### Next Steps

- Deploy your applications
- Set up monitoring (Prometheus, Grafana)
- Configure ingress controllers (NGINX, Traefik)
- Implement backup strategies for etcd
- Test cluster upgrades in staging

---

**Author**: Ademola Sobaki — Production-focused kubeadm + containerd guide (OS-agnostic)

**End of document.**

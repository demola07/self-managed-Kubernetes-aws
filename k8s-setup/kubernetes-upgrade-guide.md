# Kubernetes Upgrade Guide

Complete guide for upgrading a self-managed Kubernetes cluster from one version to another (e.g., 1.33 → 1.34).

## 📋 Upgrade Rules & Best Practices

### Version Skew Policy

- ✅ **Upgrade one minor version at a time**: 1.33 → 1.34 (NOT 1.33 → 1.35)
- ✅ **kubelet**: Can be up to 2 minor versions older than API server
- ✅ **kubectl**: Can be ±1 minor version from API server
- ✅ **Control plane components**: Should all be the same version

### Upgrade Order

```
1st Control Plane → 2nd Control Plane → 3rd Control Plane → Worker 1 → Worker 2 → ... → Worker N
```

**Critical**: Always upgrade control plane nodes before worker nodes!

### Pre-Upgrade Checklist

- [ ] Read Kubernetes release notes for target version
- [ ] Backup etcd database
- [ ] Test upgrade in staging/dev environment first
- [ ] Check addon compatibility (CNI, CSI, monitoring, etc.)
- [ ] Verify current cluster health
- [ ] Plan maintenance window
- [ ] Notify stakeholders

---

## 🔍 Pre-Upgrade Steps

### 1. Backup etcd

```bash
# On control plane node
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup-*.db
```

### 2. Check Current Cluster Status

```bash
# Check node versions
kubectl get nodes -o wide

# Check component health
kubectl get componentstatuses

# Check all pods
kubectl get pods -A

# Check for any issues
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### 3. Determine Target Version

```bash
# Example: Upgrading to 1.34
TARGET_VERSION="1.34.0"
KUBE_VERSION="1.34.0-1.1"  # Package version format
```

---

## 🎯 Upgrade Process

## Step 1: Upgrade First Control Plane Node

This is the most critical step. The first control plane node upgrades the cluster control plane.

### 1.1 Update Package Repository

```bash
# SSH to first control plane node
ssh ubuntu@<first-control-plane-ip>

# Update to v1.34 repository
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

### 1.2 Check Available Versions

```bash
# List available versions
apt-cache madison kubeadm | grep 1.34

# Example output:
#   kubeadm | 1.34.0-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
#   kubeadm | 1.34.1-1.1 | https://pkgs.k8s.io/core:/stable:/v1.34/deb  Packages
```

### 1.3 Upgrade kubeadm

```bash
# Set target version
KUBE_VERSION="1.34.0-1.1"

# Unhold kubeadm
sudo apt-mark unhold kubeadm

# Upgrade kubeadm
sudo apt-get install -y kubeadm=$KUBE_VERSION

# Hold again
sudo apt-mark hold kubeadm

# Verify
kubeadm version
# Output: kubeadm version: &version.Info{Major:"1", Minor:"34", GitVersion:"v1.34.0", ...}
```

### 1.4 Plan the Upgrade

```bash
# Dry-run to see what will be upgraded
sudo kubeadm upgrade plan

# This shows:
# - Current cluster version
# - Target version
# - Component versions that will be upgraded
# - Any warnings or issues
```

### 1.5 Apply the Upgrade

```bash
# Apply the upgrade (this upgrades the control plane)
sudo kubeadm upgrade apply v1.34.0

# You'll see output like:
# [upgrade/successful] SUCCESS! Your cluster was upgraded to "v1.34.0". Enjoy!
```

### 1.6 Drain the Node

```bash
# Get node name
NODE_NAME=$(hostname)

# Drain node (move pods to other nodes)
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data

# Node is now in SchedulingDisabled state
```

### 1.7 Upgrade kubelet and kubectl

```bash
# Unhold packages
sudo apt-mark unhold kubelet kubectl

# Upgrade
sudo apt-get install -y kubelet=$KUBE_VERSION kubectl=$KUBE_VERSION

# Hold again
sudo apt-mark hold kubelet kubectl

# Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Check status
sudo systemctl status kubelet
```

### 1.8 Uncordon the Node

```bash
# Allow pods to be scheduled on this node again
kubectl uncordon $NODE_NAME

# Verify node is Ready
kubectl get nodes
```

### 1.9 Verify First Control Plane Upgrade

```bash
# Check node version
kubectl get nodes

# Check component versions
kubectl version

# Check all pods are running
kubectl get pods -A

# Check cluster info
kubectl cluster-info
```

---

## Step 2: Upgrade Additional Control Plane Nodes

Repeat for each additional control plane node (if you have HA setup).

### 2.1 SSH to Next Control Plane Node

```bash
ssh ubuntu@<second-control-plane-ip>
```

### 2.2 Update Repository

```bash
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

### 2.3 Upgrade kubeadm

```bash
KUBE_VERSION="1.34.0-1.1"

sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$KUBE_VERSION
sudo apt-mark hold kubeadm

kubeadm version
```

### 2.4 Upgrade Node

```bash
# For additional control plane nodes, use 'upgrade node' (NOT 'upgrade apply')
sudo kubeadm upgrade node
```

### 2.5 Drain Node

```bash
NODE_NAME=$(hostname)
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data
```

### 2.6 Upgrade kubelet and kubectl

```bash
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$KUBE_VERSION kubectl=$KUBE_VERSION
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 2.7 Uncordon Node

```bash
kubectl uncordon $NODE_NAME
kubectl get nodes
```

### 2.8 Repeat for Third Control Plane

If you have a third control plane node, repeat steps 2.1-2.7.

---

## Step 3: Upgrade Worker Nodes

Upgrade worker nodes **one at a time** to maintain application availability.

### 3.1 SSH to Worker Node

```bash
ssh ubuntu@<worker-node-ip>
```

### 3.2 Update Repository

```bash
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
```

### 3.3 Upgrade kubeadm

```bash
KUBE_VERSION="1.34.0-1.1"

sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$KUBE_VERSION
sudo apt-mark hold kubeadm
```

### 3.4 Upgrade Node Configuration

```bash
sudo kubeadm upgrade node
```

### 3.5 Drain Node (from Control Plane)

```bash
# Run this from a control plane node
kubectl drain <worker-node-name> --ignore-daemonsets --delete-emptydir-data

# This moves all pods to other worker nodes
```

### 3.6 Upgrade kubelet and kubectl

```bash
# Back on the worker node
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$KUBE_VERSION kubectl=$KUBE_VERSION
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### 3.7 Uncordon Node (from Control Plane)

```bash
# Run this from a control plane node
kubectl uncordon <worker-node-name>

# Verify
kubectl get nodes
```

### 3.8 Repeat for All Workers

Repeat steps 3.1-3.7 for each worker node, **one at a time**.

**Wait** for each worker to be fully upgraded and Ready before moving to the next.

---

## 🔍 Post-Upgrade Verification

### Check All Nodes

```bash
# All nodes should show new version
kubectl get nodes

# Expected output:
# NAME                              STATUS   ROLES           AGE   VERSION
# k8s-cluster-dev-control-plane-1   Ready    control-plane   30d   v1.34.0
# k8s-cluster-dev-control-plane-2   Ready    control-plane   30d   v1.34.0
# k8s-cluster-dev-worker-1          Ready    <none>          30d   v1.34.0
# k8s-cluster-dev-worker-2          Ready    <none>          30d   v1.34.0
```

### Check Component Versions

```bash
# API server version
kubectl version

# Component status
kubectl get componentstatuses
```

### Check All Pods

```bash
# All pods should be running
kubectl get pods -A

# Check for any issues
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | head -20
```

### Check Cluster Health

```bash
# Cluster info
kubectl cluster-info

# Node details
kubectl describe nodes

# Check CNI (Cilium)
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Test Application Workloads

```bash
# Deploy test application
kubectl run test-nginx --image=nginx --restart=Never

# Check it's running
kubectl get pod test-nginx

# Cleanup
kubectl delete pod test-nginx
```

---

## 🚨 Troubleshooting

### Upgrade Fails on Control Plane

```bash
# Check kubeadm logs
sudo journalctl -xeu kubelet

# Check upgrade status
sudo kubeadm upgrade plan

# Rollback if needed (before applying)
# Just reinstall previous kubeadm version
```

### Node Won't Drain

```bash
# Force drain (use carefully)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force

# Or skip specific pods
kubectl drain <node> --ignore-daemonsets --pod-selector='app!=critical-app'
```

### Kubelet Won't Start

```bash
# Check kubelet status
sudo systemctl status kubelet

# Check logs
sudo journalctl -xeu kubelet -f

# Common issues:
# - Container runtime not running
# - Configuration mismatch
# - Certificate issues

# Restart containerd
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

### Pods Not Scheduling

```bash
# Check node status
kubectl describe node <node-name>

# Check for taints
kubectl get nodes -o json | jq '.items[].spec.taints'

# Remove taint if needed
kubectl taint nodes <node-name> node.kubernetes.io/unschedulable-
```

### Version Mismatch

```bash
# Check all component versions
kubectl get nodes -o wide
kubeadm version
kubelet --version
kubectl version

# If mismatch, reinstall correct version
KUBE_VERSION="1.34.0-1.1"
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$KUBE_VERSION kubectl=$KUBE_VERSION
sudo apt-mark hold kubelet kubectl
sudo systemctl restart kubelet
```

---

## 📝 Automation Script

### Control Plane Upgrade Script

```bash
#!/bin/bash
# upgrade-control-plane.sh

set -e

TARGET_VERSION="1.34.0-1.1"
NODE_NAME=$(hostname)

echo "=== Upgrading Control Plane Node: $NODE_NAME ==="

# Update repository
echo "Updating package repository..."
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

# Upgrade kubeadm
echo "Upgrading kubeadm..."
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$TARGET_VERSION
sudo apt-mark hold kubeadm

# Check if this is the first control plane
if [ "$1" == "first" ]; then
    echo "Running kubeadm upgrade apply..."
    sudo kubeadm upgrade apply v1.34.0 -y
else
    echo "Running kubeadm upgrade node..."
    sudo kubeadm upgrade node
fi

# Drain node
echo "Draining node..."
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data

# Upgrade kubelet and kubectl
echo "Upgrading kubelet and kubectl..."
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$TARGET_VERSION kubectl=$TARGET_VERSION
sudo apt-mark hold kubelet kubectl

# Restart kubelet
echo "Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Uncordon node
echo "Uncordoning node..."
kubectl uncordon $NODE_NAME

echo "=== Upgrade Complete for $NODE_NAME ==="
kubectl get nodes
```

### Worker Node Upgrade Script

```bash
#!/bin/bash
# upgrade-worker.sh

set -e

TARGET_VERSION="1.34.0-1.1"
NODE_NAME=$(hostname)

echo "=== Upgrading Worker Node: $NODE_NAME ==="

# Update repository
echo "Updating package repository..."
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

# Upgrade kubeadm
echo "Upgrading kubeadm..."
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=$TARGET_VERSION
sudo apt-mark hold kubeadm

# Upgrade node
echo "Running kubeadm upgrade node..."
sudo kubeadm upgrade node

# Upgrade kubelet and kubectl
echo "Upgrading kubelet and kubectl..."
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=$TARGET_VERSION kubectl=$TARGET_VERSION
sudo apt-mark hold kubelet kubectl

# Restart kubelet
echo "Restarting kubelet..."
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "=== Upgrade Complete for $NODE_NAME ==="
echo "Run 'kubectl uncordon $NODE_NAME' from control plane"
```

### Usage

```bash
# On first control plane node
chmod +x upgrade-control-plane.sh
./upgrade-control-plane.sh first

# On additional control plane nodes
./upgrade-control-plane.sh

# On worker nodes
chmod +x upgrade-worker.sh
./upgrade-worker.sh

# Then from control plane, uncordon the worker
kubectl uncordon <worker-node-name>
```

---

## 📊 Upgrade Checklist

### Pre-Upgrade
- [ ] Backup etcd
- [ ] Read release notes
- [ ] Test in staging
- [ ] Check addon compatibility
- [ ] Verify cluster health
- [ ] Schedule maintenance window

### During Upgrade
- [ ] Upgrade first control plane (kubeadm upgrade apply)
- [ ] Upgrade additional control planes (kubeadm upgrade node)
- [ ] Upgrade workers one at a time
- [ ] Verify each node before proceeding

### Post-Upgrade
- [ ] All nodes show new version
- [ ] All pods are running
- [ ] Cluster components healthy
- [ ] Applications functioning
- [ ] Update documentation
- [ ] Notify stakeholders

---

## 🎓 Key Takeaways

1. **Always upgrade one minor version at a time** (1.33 → 1.34, not 1.33 → 1.35)
2. **Control plane first, workers second**
3. **First control plane uses `kubeadm upgrade apply`**
4. **Other nodes use `kubeadm upgrade node`**
5. **Drain nodes before upgrading kubelet**
6. **Upgrade one node at a time**
7. **Test in staging first**
8. **Backup etcd before starting**

---

## 📚 Additional Resources

- [Official Kubernetes Upgrade Documentation](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [Kubernetes Release Notes](https://kubernetes.io/releases/)
- [Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/)
- [kubeadm Upgrade Command Reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-upgrade/)

---

**Author**: Ademola Sobaki — Kubernetes Upgrade Guide  
**Last Updated**: November 2025  
**Kubernetes Version**: 1.33.x → 1.34.x

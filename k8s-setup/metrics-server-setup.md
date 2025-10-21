# 📊 Kubernetes Metrics Server Installation Guide

The Metrics Server collects resource metrics from Kubelets and exposes them in the Kubernetes API server through the Metrics API. This enables `kubectl top` commands and Horizontal Pod Autoscaling (HPA).

---

## Prerequisites

- Running Kubernetes cluster
- `kubectl` configured and connected to your cluster
- Cluster admin access

---

## 1. Install Metrics Server

### Option A: Using Official Manifest

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Option B: Using Helm

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args[0]="--kubelet-insecure-tls" \
  --set args[1]="--kubelet-preferred-address-types=InternalIP"
```

---

## 2. Configure for Self-Managed Clusters

For self-managed clusters (like kubeadm), you may need to add flags for TLS and address resolution.

### Edit the Deployment

```bash
kubectl edit deployment metrics-server -n kube-system
```

Add these args under `spec.template.spec.containers[0].args`:

```yaml
args:
  - --cert-dir=/tmp
  - --secure-port=10250
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
  - --kubelet-insecure-tls  # Add this for self-signed certs
```

### Or Apply This Patch Directly

```bash
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-preferred-address-types=InternalIP"
  }
]'
```

---

## 3. Verify Installation

### Check Metrics Server Pod

```bash
kubectl get deployment metrics-server -n kube-system
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
metrics-server-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### Wait for Metrics to Be Available

It may take 1-2 minutes for metrics to start being collected.

```bash
# Check if metrics API is responding
kubectl get apiservices | grep metrics

# Should show:
# v1beta1.metrics.k8s.io    kube-system/metrics-server   True
```

---

## 4. Test Metrics Server

### View Node Metrics

```bash
kubectl top nodes
```

Expected output:
```
NAME                              CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
k8s-cluster-dev-control-plane-1   100m         5%     1500Mi          40%
k8s-cluster-dev-worker-1          50m          2%     800Mi           20%
```

### View Pod Metrics

```bash
kubectl top pods -A
```

### View Specific Namespace

```bash
kubectl top pods -n kube-system
```

---

## 5. Troubleshooting

### Metrics Not Available

If you see `error: Metrics API not available`, check:

```bash
# Check metrics-server logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# Check if metrics-server can reach kubelets
kubectl describe apiservice v1beta1.metrics.k8s.io
```

### Common Issues

#### Issue 1: TLS Certificate Errors

**Error**: `x509: cannot validate certificate`

**Solution**: Add `--kubelet-insecure-tls` flag (already covered in step 2)

#### Issue 2: Unable to Reach Kubelet

**Error**: `unable to fetch metrics from Kubelet`

**Solution**: Add `--kubelet-preferred-address-types=InternalIP`

#### Issue 3: Metrics Server CrashLoopBackOff

**Check logs**:
```bash
kubectl logs -n kube-system deployment/metrics-server
```

**Common fix**: Ensure DNS is working in the cluster
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

---

## 6. Complete Installation Script

Save this as `install-metrics-server.sh`:

```bash
#!/bin/bash
set -e

echo "Installing Metrics Server..."

# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "Waiting for deployment to be created..."
sleep 5

# Patch for self-managed clusters
echo "Patching metrics-server for self-managed cluster..."
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-preferred-address-types=InternalIP"
  }
]'

echo "Waiting for metrics-server to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system

echo "Metrics Server installed successfully!"
echo ""
echo "Testing metrics collection (may take 1-2 minutes)..."
sleep 60

kubectl top nodes
```

Run it:
```bash
chmod +x install-metrics-server.sh
./install-metrics-server.sh
```

---

## 7. Using Metrics Server

### Horizontal Pod Autoscaler (HPA)

Once metrics-server is running, you can use HPA:

```bash
# Create an HPA
kubectl autoscale deployment myapp --cpu-percent=50 --min=1 --max=10

# View HPA status
kubectl get hpa
```

### Monitor Resource Usage

```bash
# Watch node metrics in real-time
watch kubectl top nodes

# Watch pod metrics
watch kubectl top pods -A

# Sort pods by CPU usage
kubectl top pods -A --sort-by=cpu

# Sort pods by memory usage
kubectl top pods -A --sort-by=memory
```

---

## 8. Uninstall Metrics Server

If you need to remove metrics-server:

```bash
kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Or if installed via Helm:
```bash
helm uninstall metrics-server -n kube-system
```

---

## Configuration Reference

### Key Flags

| Flag | Description |
|------|-------------|
| `--kubelet-insecure-tls` | Skip kubelet TLS verification (needed for self-signed certs) |
| `--kubelet-preferred-address-types` | Order of node address types to use |
| `--metric-resolution` | Interval for scraping metrics (default: 60s) |
| `--kubelet-use-node-status-port` | Use the port in node status instead of kubelet port |

### Resource Requirements

Default resources for metrics-server:
- **CPU**: 100m (request), 1000m (limit)
- **Memory**: 200Mi (request), 1000Mi (limit)

---

## Additional Resources

- [Official Metrics Server Documentation](https://github.com/kubernetes-sigs/metrics-server)
- [Kubernetes Metrics API](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---


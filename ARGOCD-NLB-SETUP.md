# ArgoCD NLB Setup Guide

Complete guide for exposing ArgoCD (or any Kubernetes service) via the existing Network Load Balancer using Terraform.

## 🎯 Overview

This setup allows you to:
- ✅ Access ArgoCD via NLB (e.g., `http://<nlb-dns>:8080`)
- ✅ Enable/disable via Terraform variable
- ✅ Fully managed infrastructure (no manual AWS CLI commands)
- ✅ Reusable for other services (Grafana, Prometheus, etc.)

## 📋 Architecture

```
Internet
   ↓
NLB (k8s-cluster-dev-app-nlb)
   ├── Port 80 → Gateway API HTTP (32540)
   ├── Port 443 → Gateway API HTTPS (31608)
   └── Port 8080 → ArgoCD (30080)  ← New
          ↓
   Worker Nodes:30080
          ↓
   ArgoCD Server Pods
```

## 🚀 Step-by-Step Setup

### Step 1: Install ArgoCD in Kubernetes

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### Step 2: Create NodePort Service for ArgoCD

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: argocd-server-nodeport
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-server
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
  - name: http
    port: 80
    targetPort: 8080
    nodePort: 30080  # Must match Terraform argocd_nodeport variable
    protocol: TCP
  - name: https
    port: 443
    targetPort: 8080
    nodePort: 30443  # Optional: HTTPS access
    protocol: TCP
EOF
```

### Step 3: Verify NodePort is Listening

```bash
# Check service
kubectl get svc -n argocd argocd-server-nodeport

# Expected output:
# NAME                      TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                     AGE
# argocd-server-nodeport    NodePort   10.96.123.45    <none>        80:30080/TCP,443:30443/TCP  1m

# Test from worker node
ssh ubuntu@<worker-ip>
curl http://localhost:30080
# Should return ArgoCD HTML
```

### Step 4: Enable ArgoCD NLB in Terraform

Update your `dev.tfvars`:

```hcl
# ArgoCD NLB Configuration
enable_argocd_nlb      = true   # Enable ArgoCD access via NLB
argocd_nodeport        = 30080  # Must match Kubernetes NodePort
argocd_listener_port   = 8080   # External port on NLB
```

### Step 5: Apply Terraform

```bash
# Review changes
terraform plan

# Expected changes:
# + module.argocd_nlb[0].aws_lb_target_group.service
# + module.argocd_nlb[0].aws_lb_listener.service
# + module.argocd_nlb[0].aws_lb_target_group_attachment.service[0]
# + module.argocd_nlb[0].aws_lb_target_group_attachment.service[1]
# + module.argocd_nlb[0].aws_lb_target_group_attachment.service[2]
# + module.argocd_nlb[0].aws_vpc_security_group_ingress_rule.service_nodeport

# Apply
terraform apply
```

### Step 6: Get ArgoCD URL

```bash
# Get NLB DNS
terraform output argocd_nlb_url

# Output: http://k8s-cluster-dev-app-nlb-abc123.elb.us-east-1.amazonaws.com:8080
```

### Step 7: Access ArgoCD

```bash
# Open in browser
open $(terraform output -raw argocd_nlb_url)

# Or use curl
curl $(terraform output -raw argocd_nlb_url)
```

### Step 8: Get ArgoCD Admin Password

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Login:
# Username: admin
# Password: <output from above command>
```

## 🔧 Configuration Options

### Customize Ports

```hcl
# dev.tfvars

# Use different NodePort
argocd_nodeport = 30081

# Use different external port
argocd_listener_port = 9090
```

### Customize Health Checks

```hcl
# main.tf

module "argocd_nlb" {
  # ... other config ...
  
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3
  health_check_interval            = 5
  deregistration_delay             = 60
}
```

## 🔄 Enable/Disable ArgoCD NLB

### Enable

```hcl
# dev.tfvars
enable_argocd_nlb = true
```

```bash
terraform apply
```

### Disable

```hcl
# dev.tfvars
enable_argocd_nlb = false
```

```bash
terraform apply
# This will remove:
# - NLB listener
# - Target group
# - Target group attachments
# - Security group rule
```

## 🔍 Verification & Troubleshooting

### Check Target Group Health

```bash
# Get target group ARN
terraform output argocd_target_group_arn

# Check health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw argocd_target_group_arn)

# Expected output:
# {
#   "TargetHealthDescriptions": [
#     {
#       "Target": {
#         "Id": "i-xxx",
#         "Port": 30080
#       },
#       "TargetHealth": {
#         "State": "healthy"
#       }
#     }
#   ]
# }
```

### Check NLB Listeners

```bash
# Get NLB ARN
terraform output app_loadbalancer_arn

# List all listeners
aws elbv2 describe-listeners \
  --load-balancer-arn $(terraform output -raw app_loadbalancer_arn)

# Should show listeners on ports 80, 443, and 8080
```

### Check Security Group

```bash
# Verify port 30080 is open
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw worker_security_group_id) \
  | grep -A 5 30080
```

### Test from Worker Node

```bash
# SSH to worker
ssh ubuntu@<worker-ip>

# Test ArgoCD locally
curl http://localhost:30080

# Should return ArgoCD HTML
```

### Common Issues

#### 1. Targets Unhealthy

**Problem**: Target group shows unhealthy targets

**Solution**:
```bash
# Check if ArgoCD pods are running
kubectl get pods -n argocd

# Check if NodePort service exists
kubectl get svc -n argocd argocd-server-nodeport

# Check if port is listening
ssh ubuntu@<worker-ip>
sudo netstat -tlnp | grep 30080
```

#### 2. Connection Timeout

**Problem**: Can't access ArgoCD via NLB

**Solution**:
```bash
# Check security group allows port 30080
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw worker_security_group_id) \
  | grep 30080

# Check NLB listener exists
aws elbv2 describe-listeners \
  --load-balancer-arn $(terraform output -raw app_loadbalancer_arn) \
  | grep 8080
```

#### 3. 502 Bad Gateway

**Problem**: NLB returns 502 error

**Solution**:
```bash
# Check ArgoCD pods are healthy
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Restart ArgoCD if needed
kubectl rollout restart deployment argocd-server -n argocd
```

## 🎨 Add More Services

The module is reusable for any service!

### Example: Add Grafana

```hcl
# variables.tf
variable "enable_grafana_nlb" {
  description = "Enable Grafana access via NLB"
  type        = bool
  default     = false
}

variable "grafana_nodeport" {
  description = "Kubernetes NodePort for Grafana"
  type        = number
  default     = 30081
}

variable "grafana_listener_port" {
  description = "External port on NLB for Grafana"
  type        = number
  default     = 3000
}

# main.tf
module "grafana_nlb" {
  count  = var.enable_grafana_nlb ? 1 : 0
  source = "./modules/nlb-service"

  project_name               = var.project_name
  environment                = var.environment
  service_name               = "grafana"
  vpc_id                     = module.vpc.vpc_id
  load_balancer_arn          = module.app_loadbalancer.load_balancer_arn
  worker_instance_ids        = module.worker_nodes.instance_ids
  worker_security_group_id   = module.security_groups.worker_sg_id

  nodeport      = var.grafana_nodeport
  listener_port = var.grafana_listener_port
}

# outputs.tf
output "grafana_nlb_url" {
  description = "URL to access Grafana via NLB"
  value       = var.enable_grafana_nlb ? "http://${module.app_loadbalancer.load_balancer_dns}:${var.grafana_listener_port}" : "Grafana NLB not enabled"
}

# dev.tfvars
enable_grafana_nlb      = true
grafana_nodeport        = 30081
grafana_listener_port   = 3000
```

## 🔒 Security Considerations

### 1. Use HTTPS

ArgoCD supports TLS termination:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server-nodeport
  namespace: argocd
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
  - name: https
    port: 443
    targetPort: 8443  # ArgoCD HTTPS port
    nodePort: 30443
    protocol: TCP
```

Update Terraform:
```hcl
argocd_nodeport      = 30443
argocd_listener_port = 443
```

### 2. Restrict Access

Use security groups to limit access:

```hcl
# modules/nlb-service/main.tf
resource "aws_vpc_security_group_ingress_rule" "service_nodeport" {
  security_group_id = var.worker_security_group_id
  description       = "${var.service_name} NodePort for NLB"
  
  from_port   = var.nodeport
  to_port     = var.nodeport
  ip_protocol = "tcp"
  cidr_ipv4   = "YOUR_OFFICE_IP/32"  # Restrict to your IP
}
```

### 3. Enable Authentication

ArgoCD has built-in authentication. Always:
- ✅ Change default admin password
- ✅ Use SSO (OIDC, SAML)
- ✅ Enable RBAC
- ✅ Use TLS/HTTPS

## 📊 Monitoring

### CloudWatch Metrics

```bash
# Target group health
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name HealthyHostCount \
  --dimensions Name=TargetGroup,Value=targetgroup/k8s-cluster-dev-argocd/xxx \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

### ArgoCD Metrics

```bash
# Port-forward to ArgoCD metrics
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082

# View metrics
curl http://localhost:8082/metrics
```

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [AWS NLB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [Kubernetes NodePort Service](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)

## 🎓 Summary

**What You Get:**
- ✅ ArgoCD accessible via NLB
- ✅ Fully managed by Terraform
- ✅ Enable/disable with one variable
- ✅ Automatic health checks
- ✅ Reusable for other services

**Access ArgoCD:**
```bash
# Get URL
terraform output argocd_nlb_url

# Open in browser
open $(terraform output -raw argocd_nlb_url)

# Login with admin/<initial-password>
```

**Disable ArgoCD NLB:**
```hcl
# dev.tfvars
enable_argocd_nlb = false

# Apply
terraform apply
```

---

**Author**: Ademola Sobaki  
**Last Updated**: November 2025

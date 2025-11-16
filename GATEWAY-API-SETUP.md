# Gateway API + Cilium Setup Guide

Complete guide for setting up Gateway API with Cilium CNI and AWS Network Load Balancer for external traffic routing.

## 🏗️ Architecture Overview

```
                         Internet
                            |
                            ▼
                   ┌─────────────────┐
                   │   External NLB  │ ← AWS Network Load Balancer
                   │   (80/443)      │    (Public subnets)
                   └────────┬────────┘
                            │
             ┌──────────────┼──────────────┐
             │              │              │
             ▼              ▼              ▼
        ┌─────────┐    ┌─────────┐    ┌─────────┐
        │Worker 1 │    │Worker 2 │    │Worker 3 │ ← Worker Nodes
        │:30080   │    │:30080   │    │:30080   │   (Private subnets)
        │:30443   │    │:30443   │    │:30443   │
        └────┬────┘    └────┬────┘    └────┬────┘
             │              │              │
             └──────────────┼──────────────┘
                            │
                   ┌────────▼────────┐
                   │  Gateway API    │ ← Cilium Gateway Controller
                   │   (Cilium)      │
                   └────────┬────────┘
                            │
                   ┌────────▼────────┐
                   │   HTTPRoute     │ ← Routes traffic to services
                   └────────┬────────┘
                            │
                   ┌────────▼────────┐
                   │  Your Services  │ ← Application pods
                   │   & Pods        │
                   └─────────────────┘
```

## 📋 Prerequisites

- ✅ Kubernetes cluster with Cilium CNI installed
- ✅ Worker nodes in private subnets
- ✅ Public subnets for load balancer
- ✅ Security groups configured
- ✅ kubectl access to cluster

## 🚀 Step-by-Step Setup

### Step 1: Add Application Load Balancer to Terraform

#### 1.1 Update main.tf

```hcl
# main.tf

module "app_loadbalancer" {
  source = "./modules/app-loadbalancer"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  worker_instance_ids = module.worker_nodes.instance_ids

  http_nodeport  = 30080
  https_nodeport = 30443

  enable_deletion_protection = var.environment == "prod" ? true : false
}
```

#### 1.2 Update outputs.tf

```hcl
# outputs.tf

output "app_loadbalancer_dns" {
  description = "DNS name for application traffic"
  value       = module.app_loadbalancer.load_balancer_dns
}

output "app_loadbalancer_zone_id" {
  description = "Zone ID for Route53 alias records"
  value       = module.app_loadbalancer.load_balancer_zone_id
}
```

#### 1.3 Update Worker Security Group

Add these rules to allow NodePort traffic:

```hcl
# modules/security-groups/main.tf

resource "aws_security_group_rule" "worker_http_nodeport" {
  type              = "ingress"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
  description       = "HTTP NodePort for Gateway API"
}

resource "aws_security_group_rule" "worker_https_nodeport" {
  type              = "ingress"
  from_port         = 30443
  to_port           = 30443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
  description       = "HTTPS NodePort for Gateway API"
}
```

#### 1.4 Apply Terraform

```bash
terraform plan
terraform apply
```

### Step 2: Install Gateway API CRDs

```bash
# Install Gateway API v1.0.0
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# Verify installation
kubectl get crd | grep gateway
# Output:
# gatewayclasses.gateway.networking.k8s.io
# gateways.gateway.networking.k8s.io
# httproutes.gateway.networking.k8s.io
```

### Step 3: Enable Gateway API in Cilium

```bash
# Upgrade Cilium with Gateway API support
helm upgrade cilium cilium/cilium \
  --version 1.14.5 \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true

# Verify Cilium Gateway Controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium-operator

# Check GatewayClass
kubectl get gatewayclass
# Output:
# NAME     CONTROLLER                     ACCEPTED   AGE
# cilium   io.cilium/gateway-controller   True       1m
```

### Step 4: Create Gateway

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: cilium-gateway
  namespace: default
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - name: example-tls-cert  # Create this secret first
EOF
```

### Step 5: Create Gateway Service with NodePort

This is **critical** - it exposes the Gateway on specific NodePorts that match the NLB configuration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: cilium-gateway
  namespace: kube-system
  labels:
    app: cilium-gateway
spec:
  type: NodePort
  selector:
    io.cilium.gateway: "true"
  ports:
  - name: http
    port: 80
    targetPort: 80
    nodePort: 30080  # Must match NLB target group
    protocol: TCP
  - name: https
    port: 443
    targetPort: 443
    nodePort: 30443  # Must match NLB target group
    protocol: TCP
EOF
```

### Step 6: Verify Gateway Status

```bash
# Check Gateway
kubectl get gateway cilium-gateway
# Output:
# NAME             CLASS    ADDRESS   PROGRAMMED   AGE
# cilium-gateway   cilium             True         1m

# Check Gateway details
kubectl describe gateway cilium-gateway

# Check Gateway pods
kubectl get pods -n kube-system -l io.cilium.gateway=true

# Check NodePort service
kubectl get svc -n kube-system cilium-gateway
```

### Step 7: Create TLS Certificate (for HTTPS)

```bash
# Create self-signed cert for testing
openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 365 -nodes \
  -subj "/CN=example.com"

# Create Kubernetes secret
kubectl create secret tls example-tls-cert \
  --cert=tls.crt \
  --key=tls.key

# Verify
kubectl get secret example-tls-cert
```

### Step 8: Deploy Sample Application

```bash
# Create deployment
kubectl create deployment echo-server --image=ealen/echo-server:latest --replicas=3

# Expose as ClusterIP service
kubectl expose deployment echo-server --port=80 --target-port=80

# Verify
kubectl get pods -l app=echo-server
kubectl get svc echo-server
```

### Step 9: Create HTTPRoute

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: echo-route
  namespace: default
spec:
  parentRefs:
  - name: cilium-gateway
    namespace: default
  hostnames:
  - "echo.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: echo-server
      port: 80
EOF
```

### Step 10: Configure DNS

Get the load balancer DNS:

```bash
terraform output app_loadbalancer_dns
# Output: k8s-cluster-dev-app-nlb-abc123.elb.us-east-1.amazonaws.com
```

#### Option A: Route53 (Recommended)

```hcl
resource "aws_route53_record" "echo" {
  zone_id = var.route53_zone_id
  name    = "echo.example.com"
  type    = "A"

  alias {
    name                   = module.app_loadbalancer.load_balancer_dns
    zone_id                = module.app_loadbalancer.load_balancer_zone_id
    evaluate_target_health = true
  }
}
```

#### Option B: External DNS Provider

```
echo.example.com  CNAME  k8s-cluster-dev-app-nlb-abc123.elb.us-east-1.amazonaws.com
```

#### Option C: Local Testing (hosts file)

```bash
# Get NLB IP
nslookup k8s-cluster-dev-app-nlb-abc123.elb.us-east-1.amazonaws.com

# Add to /etc/hosts
sudo echo "<nlb-ip> echo.example.com" >> /etc/hosts
```

### Step 11: Test the Setup

```bash
# Test HTTP
curl http://echo.example.com

# Test HTTPS
curl https://echo.example.com

# Test with headers
curl -H "Host: echo.example.com" http://<nlb-dns>

# Expected response from echo-server:
# {
#   "host": {
#     "hostname": "echo.example.com",
#     "ip": "::ffff:10.0.x.x",
#     "ips": []
#   },
#   "http": {
#     "method": "GET",
#     "baseUrl": "",
#     "originalUrl": "/",
#     ...
#   }
# }
```

## 🔍 Verification & Troubleshooting

### Check NLB Target Health

```bash
# Get target group ARN
terraform output app_loadbalancer_http_target_group_arn

# Check health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# Expected output:
# {
#   "TargetHealthDescriptions": [
#     {
#       "Target": {
#         "Id": "i-xxx",
#         "Port": 30080
#       },
#       "HealthCheckPort": "30080",
#       "TargetHealth": {
#         "State": "healthy"
#       }
#     }
#   ]
# }
```

### Check Gateway Status

```bash
# Gateway status
kubectl get gateway -A
kubectl describe gateway cilium-gateway

# HTTPRoute status
kubectl get httproute -A
kubectl describe httproute echo-route

# Gateway pods
kubectl get pods -n kube-system -l io.cilium.gateway=true
kubectl logs -n kube-system -l io.cilium.gateway=true
```

### Test from Worker Node

```bash
# SSH to worker node
ssh ubuntu@<worker-ip>

# Test NodePort directly
curl http://localhost:30080 -H "Host: echo.example.com"

# Test from another worker
curl http://<worker-ip>:30080 -H "Host: echo.example.com"
```

### Common Issues

#### 1. Targets Unhealthy

```bash
# Check if NodePort is listening
sudo netstat -tlnp | grep 30080

# Check security group
aws ec2 describe-security-groups --group-ids <worker-sg-id> | grep 30080

# Check Gateway pods
kubectl get pods -n kube-system -l io.cilium.gateway=true
```

#### 2. 404 Not Found

```bash
# Check HTTPRoute
kubectl describe httproute echo-route

# Check backend service
kubectl get svc echo-server
kubectl get endpoints echo-server

# Check Gateway listeners
kubectl get gateway cilium-gateway -o yaml | grep -A 10 listeners
```

#### 3. Connection Timeout

```bash
# Check NLB listeners
aws elbv2 describe-listeners --load-balancer-arn <lb-arn>

# Check target group attachments
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Check worker security groups allow NodePort
```

## 📊 Monitoring

### CloudWatch Metrics

```bash
# NLB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name HealthyHostCount \
  --dimensions Name=LoadBalancer,Value=<lb-name> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

### Gateway API Metrics

```bash
# Install Prometheus (if not already)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# Cilium metrics
kubectl port-forward -n kube-system svc/cilium-agent 9090:9090

# View metrics
curl http://localhost:9090/metrics | grep cilium_gateway
```

## 🎯 Production Considerations

### 1. Enable Deletion Protection

```hcl
module "app_loadbalancer" {
  # ...
  enable_deletion_protection = true
}
```

### 2. Enable Access Logs

```hcl
resource "aws_s3_bucket" "nlb_logs" {
  bucket = "${var.project_name}-${var.environment}-nlb-logs"
}

resource "aws_lb" "app" {
  # ...
  access_logs {
    bucket  = aws_s3_bucket.nlb_logs.id
    enabled = true
  }
}
```

### 3. Use Real TLS Certificates

```bash
# Using cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: cilium-gateway
            namespace: default
EOF

# Create Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-tls-cert
  namespace: default
spec:
  secretName: example-tls-cert
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - example.com
  - "*.example.com"
EOF
```

### 4. Configure Rate Limiting

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: echo-route
spec:
  parentRefs:
  - name: cilium-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    filters:
    - type: ExtensionRef
      extensionRef:
        group: cilium.io
        kind: CiliumEnvoyConfig
        name: rate-limit
    backendRefs:
    - name: echo-server
      port: 80
```

## 📚 Additional Resources

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Cilium Gateway API Guide](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [AWS NLB Best Practices](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/network-load-balancer-best-practices.html)
- [cert-manager Documentation](https://cert-manager.io/docs/)

---

**Author**: Ademola Sobaki  
**Last Updated**: November 2025

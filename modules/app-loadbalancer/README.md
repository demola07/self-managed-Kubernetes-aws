# Application Load Balancer Module

This module creates an external Network Load Balancer (NLB) for routing application traffic to worker nodes in a self-managed Kubernetes cluster using Gateway API and Cilium CNI.

## Purpose

**This is separate from the API server load balancer.** This NLB handles external application traffic, not Kubernetes API traffic.

## Architecture

```
                    Internet
                       |
                       ▼
              ┌─────────────────┐
              │  External NLB   │ ← This module
              │  (Port 80/443)  │
              └────────┬────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │ Worker 1│   │ Worker 2│   │ Worker 3│
   │ :30080  │   │ :30080  │   │ :30080  │ ← HTTP NodePort
   │ :30443  │   │ :30443  │   │ :30443  │ ← HTTPS NodePort
   └─────────┘   └─────────┘   └─────────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
              ┌────────▼────────┐
              │  Gateway API    │
              │  (Cilium)       │
              └─────────────────┘
                       │
                  Your Pods
```

## Why Worker Nodes?

✅ **Correct**: Route traffic to worker nodes  
❌ **Incorrect**: Route traffic to control plane nodes

### Reasons:

1. **Separation of concerns**: Control plane manages cluster, workers run applications
2. **Security**: Control plane should not be exposed to external traffic
3. **Scalability**: Scale workers independently for application traffic
4. **Gateway API design**: Gateway controllers run on worker nodes
5. **Stability**: Application traffic won't impact cluster operations

## Usage

### 1. Add to Root Module

```hcl
# main.tf

module "app_loadbalancer" {
  source = "./modules/app-loadbalancer"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  worker_instance_ids = module.worker_nodes.instance_ids

  # NodePorts that Gateway API will use
  http_nodeport  = 30080
  https_nodeport = 30443

  enable_deletion_protection = false  # Set to true for production
}
```

### 2. Add Outputs

```hcl
# outputs.tf

output "app_loadbalancer_dns" {
  description = "DNS name for application load balancer"
  value       = module.app_loadbalancer.load_balancer_dns
}

output "app_loadbalancer_zone_id" {
  description = "Zone ID for Route53 alias records"
  value       = module.app_loadbalancer.load_balancer_zone_id
}
```

### 3. Update Security Groups

Ensure worker nodes allow traffic on NodePorts:

```hcl
# modules/security-groups/main.tf

# Add to worker security group
resource "aws_security_group_rule" "worker_http_nodeport" {
  type              = "ingress"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # Or restrict to NLB subnet CIDRs
  security_group_id = aws_security_group.worker.id
  description       = "HTTP NodePort for Gateway API"
}

resource "aws_security_group_rule" "worker_https_nodeport" {
  type              = "ingress"
  from_port         = 30443
  to_port           = 30443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # Or restrict to NLB subnet CIDRs
  security_group_id = aws_security_group.worker.id
  description       = "HTTPS NodePort for Gateway API"
}
```

## Gateway API Configuration

### 1. Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

### 2. Install Cilium with Gateway API Support

```bash
helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true
```

### 3. Create Gateway

```yaml
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
      - name: example-tls-cert
```

### 4. Create Gateway Service with NodePort

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cilium-gateway
  namespace: kube-system
spec:
  type: NodePort
  selector:
    io.cilium.gateway: "true"
  ports:
  - name: http
    port: 80
    targetPort: 80
    nodePort: 30080  # Must match NLB target group
  - name: https
    port: 443
    targetPort: 443
    nodePort: 30443  # Must match NLB target group
```

### 5. Create HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example-route
  namespace: default
spec:
  parentRefs:
  - name: cilium-gateway
    namespace: default
  hostnames:
  - "example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: example-service
      port: 80
```

## DNS Configuration

Point your domain to the load balancer:

### Using Route53

```hcl
resource "aws_route53_record" "app" {
  zone_id = var.route53_zone_id
  name    = "app.example.com"
  type    = "A"

  alias {
    name                   = module.app_loadbalancer.load_balancer_dns
    zone_id                = module.app_loadbalancer.load_balancer_zone_id
    evaluate_target_health = true
  }
}
```

### Using CNAME (Other DNS Providers)

```
app.example.com  CNAME  k8s-cluster-dev-app-nlb-abc123.elb.us-east-1.amazonaws.com
```

## Monitoring

### Check NLB Health

```bash
# Get target group ARNs
terraform output app_loadbalancer_http_target_group_arn
terraform output app_loadbalancer_https_target_group_arn

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>
```

### Check Gateway API Status

```bash
# Check Gateway status
kubectl get gateway -A

# Check HTTPRoutes
kubectl get httproute -A

# Check Gateway pods
kubectl get pods -n kube-system -l io.cilium.gateway=true
```

## Troubleshooting

### Targets Unhealthy

```bash
# Check if NodePort services are running
kubectl get svc -n kube-system cilium-gateway

# Check if ports are open on workers
nc -zv <worker-ip> 30080
nc -zv <worker-ip> 30443

# Check security group rules
aws ec2 describe-security-groups --group-ids <worker-sg-id>
```

### Traffic Not Reaching Pods

```bash
# Check Gateway status
kubectl describe gateway cilium-gateway

# Check HTTPRoute status
kubectl describe httproute example-route

# Check Cilium Gateway pods
kubectl logs -n kube-system -l io.cilium.gateway=true

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://cilium-gateway.kube-system.svc.cluster.local
```

## Cost Considerations

- **NLB**: ~$20/month + data processing charges
- **Data transfer**: $0.01/GB processed
- **Cross-AZ traffic**: Additional charges if enabled

## Security Best Practices

1. **Use HTTPS**: Always terminate TLS at Gateway API
2. **Restrict source IPs**: Use security groups to limit access if needed
3. **Enable deletion protection**: Set to `true` in production
4. **Monitor access logs**: Enable NLB access logs to S3
5. **Use WAF**: Consider AWS WAF for additional protection (requires ALB)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Project name for resource naming | string | - | yes |
| environment | Environment name | string | - | yes |
| vpc_id | VPC ID | string | - | yes |
| public_subnet_ids | List of public subnet IDs | list(string) | - | yes |
| worker_instance_ids | List of worker instance IDs | list(string) | - | yes |
| http_nodeport | NodePort for HTTP traffic | number | 30080 | no |
| https_nodeport | NodePort for HTTPS traffic | number | 30443 | no |
| enable_deletion_protection | Enable deletion protection | bool | false | no |

## Outputs

| Name | Description |
|------|-------------|
| load_balancer_dns | DNS name of the load balancer |
| load_balancer_arn | ARN of the load balancer |
| load_balancer_zone_id | Zone ID for Route53 |
| http_target_group_arn | ARN of HTTP target group |
| https_target_group_arn | ARN of HTTPS target group |

## References

- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Cilium Gateway API Guide](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [AWS NLB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)

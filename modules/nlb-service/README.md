# NLB Service Module

Reusable module for exposing additional Kubernetes services (like ArgoCD, Grafana, etc.) through the existing Network Load Balancer.

## Features

- ✅ Creates target group for the service
- ✅ Registers worker nodes to target group
- ✅ Adds listener to existing NLB
- ✅ Updates worker security group
- ✅ Configurable health checks
- ✅ Can be enabled/disabled via `count`

## Usage

### Example: Expose ArgoCD

```hcl
# main.tf

module "argocd_nlb" {
  count  = var.enable_argocd_nlb ? 1 : 0  # Enable/disable via variable
  source = "./modules/nlb-service"

  project_name               = var.project_name
  environment                = var.environment
  service_name               = "argocd"
  vpc_id                     = module.vpc.vpc_id
  load_balancer_arn          = module.app_loadbalancer.load_balancer_arn
  worker_instance_ids        = module.worker_nodes.instance_ids
  worker_security_group_id   = module.security_groups.worker_sg_id

  nodeport      = 30080  # Kubernetes NodePort for ArgoCD
  listener_port = 8080   # External port on NLB
}
```

### Example: Expose Multiple Services

```hcl
# ArgoCD
module "argocd_nlb" {
  count  = var.enable_argocd_nlb ? 1 : 0
  source = "./modules/nlb-service"

  project_name               = var.project_name
  environment                = var.environment
  service_name               = "argocd"
  vpc_id                     = module.vpc.vpc_id
  load_balancer_arn          = module.app_loadbalancer.load_balancer_arn
  worker_instance_ids        = module.worker_nodes.instance_ids
  worker_security_group_id   = module.security_groups.worker_sg_id

  nodeport      = 30080
  listener_port = 8080
}

# Grafana
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

  nodeport      = 30081
  listener_port = 3000
}
```

## Variables

### Add to `variables.tf`

```hcl
variable "enable_argocd_nlb" {
  description = "Enable ArgoCD access via NLB"
  type        = bool
  default     = false
}

variable "argocd_nodeport" {
  description = "Kubernetes NodePort for ArgoCD"
  type        = number
  default     = 30080
}

variable "argocd_listener_port" {
  description = "External port on NLB for ArgoCD"
  type        = number
  default     = 8080
}
```

### Add to `dev.tfvars`

```hcl
# ArgoCD Configuration
enable_argocd_nlb      = true   # Set to false to disable
argocd_nodeport        = 30080
argocd_listener_port   = 8080
```

## Outputs

### Add to `outputs.tf`

```hcl
output "argocd_nlb_url" {
  description = "URL to access ArgoCD via NLB"
  value       = var.enable_argocd_nlb ? "http://${module.app_loadbalancer.load_balancer_dns}:${var.argocd_listener_port}" : "ArgoCD NLB not enabled"
}

output "argocd_target_group_arn" {
  description = "ARN of ArgoCD target group"
  value       = var.enable_argocd_nlb ? module.argocd_nlb[0].target_group_arn : null
}
```

## Kubernetes Service Configuration

Your Kubernetes service must use NodePort type:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
  - name: http
    port: 80
    targetPort: 8080
    nodePort: 30080  # Must match Terraform nodeport variable
    protocol: TCP
```

## Architecture

```
Internet
   ↓
NLB (existing)
   ├── Port 80 → Gateway API (32540)
   ├── Port 443 → Gateway API (31608)
   └── Port 8080 → ArgoCD (30080)  ← New listener
          ↓
   Worker Nodes:30080
          ↓
   ArgoCD Pods
```

## Enable/Disable Service

### Enable ArgoCD

```bash
# In dev.tfvars
enable_argocd_nlb = true

# Apply
terraform apply
```

### Disable ArgoCD

```bash
# In dev.tfvars
enable_argocd_nlb = false

# Apply (will remove listener, target group, and security rule)
terraform apply
```

## Health Checks

Default health check settings:
- Protocol: TCP
- Port: Same as NodePort
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 2 consecutive failures
- Interval: 10 seconds

Customize via variables:

```hcl
module "argocd_nlb" {
  # ... other config ...
  
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 3
  health_check_interval            = 5
}
```

## Security

The module automatically:
- ✅ Opens the NodePort on worker security group (0.0.0.0/0)
- ✅ Creates target group with health checks
- ✅ Registers all worker nodes

**Note**: The NodePort is exposed to the internet via the NLB. Ensure your application has proper authentication!

## Troubleshooting

### Targets Unhealthy

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw argocd_target_group_arn)

# Check if NodePort is listening on worker
ssh ubuntu@<worker-ip>
sudo netstat -tlnp | grep 30080

# Check Kubernetes service
kubectl get svc -n argocd argocd-server
```

### Can't Access Service

```bash
# Get NLB DNS
terraform output app_loadbalancer_dns

# Test connection
curl http://<nlb-dns>:8080

# Check security group
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw worker_security_group_id) \
  | grep 30080
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| project_name | Project name | string | - | yes |
| environment | Environment name | string | - | yes |
| service_name | Service name | string | - | yes |
| vpc_id | VPC ID | string | - | yes |
| load_balancer_arn | NLB ARN | string | - | yes |
| worker_instance_ids | Worker instance IDs | list(string) | - | yes |
| worker_security_group_id | Worker SG ID | string | - | yes |
| nodeport | Kubernetes NodePort | number | - | yes |
| listener_port | NLB listener port | number | - | yes |
| health_check_healthy_threshold | Healthy threshold | number | 2 | no |
| health_check_unhealthy_threshold | Unhealthy threshold | number | 2 | no |
| health_check_interval | Check interval (seconds) | number | 10 | no |
| deregistration_delay | Deregistration delay (seconds) | number | 30 | no |

## Outputs

| Name | Description |
|------|-------------|
| target_group_arn | Target group ARN |
| target_group_name | Target group name |
| listener_arn | Listener ARN |
| listener_port | Listener port |
| nodeport | NodePort |

## Example: Complete Setup

See the main repository README for a complete example of setting up ArgoCD with this module.

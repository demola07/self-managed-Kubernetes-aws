# 🔧 Manual AWS Infrastructure Setup for Kubernetes Cluster

Step-by-step guide to manually create the same infrastructure as the Terraform configuration.

---

## 1. Create VPC

**VPC Dashboard → Create VPC**

- **Name**: `k8s-cluster-dev-vpc`
- **IPv4 CIDR**: `10.0.0.0/16`
- **Tenancy**: Default
- **Enable DNS hostnames**: Yes
- **Enable DNS resolution**: Yes

---

## 2. Create Subnets

### Public Subnets (for Bastion & NAT Gateways)

**VPC → Subnets → Create subnet**

**Public Subnet 1:**
- **Name**: `k8s-cluster-dev-public-subnet-1`
- **VPC**: Select your VPC
- **AZ**: `us-east-1a`
- **CIDR**: `10.0.1.0/24`

**Public Subnet 2:**
- **Name**: `k8s-cluster-dev-public-subnet-2`
- **AZ**: `us-east-1b`
- **CIDR**: `10.0.2.0/24`

### Private Subnets (for K8s Nodes)

**Private Subnet 1:**
- **Name**: `k8s-cluster-dev-private-subnet-1`
- **AZ**: `us-east-1a`
- **CIDR**: `10.0.11.0/24`

**Private Subnet 2:**
- **Name**: `k8s-cluster-dev-private-subnet-2`
- **AZ**: `us-east-1b`
- **CIDR**: `10.0.12.0/24`

---

## 3. Create Internet Gateway

**VPC → Internet Gateways → Create**

- **Name**: `k8s-cluster-dev-igw`
- **Attach to VPC**: Select your VPC

---

## 4. Create NAT Gateways

**VPC → NAT Gateways → Create**

### NAT Gateway 1:
- **Name**: `k8s-cluster-dev-nat-1`
- **Subnet**: `k8s-cluster-dev-public-subnet-1`
- **Elastic IP**: Click "Allocate Elastic IP"

### NAT Gateway 2:
- **Name**: `k8s-cluster-dev-nat-2`
- **Subnet**: `k8s-cluster-dev-public-subnet-2`
- **Elastic IP**: Click "Allocate Elastic IP"

---

## 5. Create Route Tables

### Public Route Table

**VPC → Route Tables → Create**

- **Name**: `k8s-cluster-dev-public-rt`
- **VPC**: Select your VPC

**Add Routes:**
- Destination: `0.0.0.0/0` → Target: Internet Gateway

**Associate Subnets:**
- `k8s-cluster-dev-public-subnet-1`
- `k8s-cluster-dev-public-subnet-2`

### Private Route Tables

**Private RT 1:**
- **Name**: `k8s-cluster-dev-private-rt-1`
- **Route**: `0.0.0.0/0` → NAT Gateway 1
- **Associate**: `k8s-cluster-dev-private-subnet-1`

**Private RT 2:**
- **Name**: `k8s-cluster-dev-private-rt-2`
- **Route**: `0.0.0.0/0` → NAT Gateway 2
- **Associate**: `k8s-cluster-dev-private-subnet-2`

---

## 6. Create Security Groups

### Bastion Security Group

**EC2 → Security Groups → Create**

- **Name**: `k8s-cluster-dev-bastion-sg`
- **Description**: Security group for bastion host
- **VPC**: Select your VPC

**Inbound Rules:**
- Type: SSH, Port: 22, Source: Your IP (e.g., `0.0.0.0/0` or specific IP)

**Outbound Rules:**
- Type: All traffic, Destination: `0.0.0.0/0`

### Control Plane Security Group

- **Name**: `k8s-cluster-dev-control-plane-sg`

**Inbound Rules:**
- SSH (22) from Bastion SG
- TCP 6443 from VPC CIDR (`10.0.0.0/16`)
- TCP 6443 from Bastion SG
- TCP 10250 from VPC CIDR
- TCP 10257 from VPC CIDR
- TCP 10259 from VPC CIDR
- All traffic from Control Plane SG (self-reference)
- All traffic from Worker SG

**Outbound Rules:**
- All traffic to `0.0.0.0/0`

### Worker Security Group

- **Name**: `k8s-cluster-dev-worker-sg`

**Inbound Rules:**
- SSH (22) from Bastion SG
- TCP 10250 from Control Plane SG
- TCP 30000-32767 from VPC CIDR
- All traffic from Worker SG (self-reference)
- All traffic from Control Plane SG

**Outbound Rules:**
- All traffic to `0.0.0.0/0`

---

## 7. Create IAM Roles and Policies

You need **three separate IAM roles**: one for bastion, one for control plane, and one for workers.

Choose between **Simple Setup** (AWS managed policies) or **Production Setup** (custom policies with least privilege).

---

### **Option A: Simple Setup (AWS Managed Policies)**

Faster setup using AWS managed policies. Good for learning/testing.

#### 7.1 Bastion IAM Role

**IAM → Roles → Create role**

- **Trusted entity**: AWS service → EC2
- **Name**: `k8s-cluster-dev-bastion-role`
- **Attach policies**: 
  - `AmazonSSMManagedInstanceCore`

#### 7.2 Control Plane IAM Role

**IAM → Roles → Create role**

- **Trusted entity**: AWS service → EC2
- **Name**: `k8s-cluster-dev-control-plane-role`
- **Attach policies**:
  - `AmazonSSMManagedInstanceCore`
  - `AmazonEC2FullAccess`
  - `ElasticLoadBalancingFullAccess`
  - `AmazonEC2ContainerRegistryReadOnly`

#### 7.3 Worker IAM Role

**IAM → Roles → Create role**

- **Trusted entity**: AWS service → EC2
- **Name**: `k8s-cluster-dev-worker-role`
- **Attach policies**:
  - `AmazonSSMManagedInstanceCore`
  - `AmazonEC2ReadOnlyAccess`
  - `AmazonEC2ContainerRegistryReadOnly`

> **Note**: If using Cilium CNI, you don't need `AmazonEKS_CNI_Policy` (only needed for AWS VPC CNI)

---

### **Option B: Production Setup (Custom Policies - Recommended)**

More secure with explicit permissions following the principle of least privilege.

#### 7.1 Bastion IAM Role

**IAM → Roles → Create role**

- **Trusted entity**: AWS service → EC2
- **Name**: `k8s-cluster-dev-bastion-role`
- **Attach policies**: `AmazonSSMManagedInstanceCore`

#### 7.2 Control Plane IAM Role

**IAM → Roles → Create role**

- **Trusted entity**: AWS service → EC2
- **Name**: `k8s-cluster-dev-control-plane-role`

**Attach managed policies:**
- `AmazonSSMManagedInstanceCore`

**Create and attach inline policy** (`k8s-control-plane-policy`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyVolume",
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteVolume",
        "ec2:DetachVolume",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeVpcAttribute"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

### 7.3 Worker IAM Role

**IAM → Roles → Create role**

- **Trusted entity**: AWS service → EC2
- **Name**: `k8s-cluster-dev-worker-role`

**Attach managed policies:**
- `AmazonSSMManagedInstanceCore`

**Create and attach inline policy** (`k8s-worker-policy`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```

---

**How to attach policies in AWS Console:**
1. Go to **IAM → Roles → Create role**
2. Select **AWS service** → **EC2**
3. Click **Next** to permissions
4. Search and select the policies listed above
5. For custom policies (Option B): Click **Create policy** → **JSON** tab → Paste the JSON
6. Name the role and create

---

## 8. Create Key Pair

**EC2 → Key Pairs → Create**

- **Name**: `k8s-cluster-dev-key`
- **Type**: RSA
- **Format**: `.pem`
- **Download** and save securely

---

## 9. Launch Bastion Instance

**EC2 → Instances → Launch Instance**

- **Name**: `k8s-cluster-dev-bastion`
- **AMI**: Ubuntu Server 22.04 LTS
- **Instance type**: `t3.micro`
- **Key pair**: `k8s-cluster-dev-key`
- **Network**: Your VPC
- **Subnet**: `k8s-cluster-dev-public-subnet-1`
- **Auto-assign public IP**: Enable
- **Security group**: `k8s-cluster-dev-bastion-sg`
- **IAM instance profile**: `k8s-cluster-dev-bastion-role`
- **Storage**: 20 GB gp3, encrypted

**Advanced → User data:**
```bash
#!/bin/bash
apt-get update
apt-get install -y curl wget vim
```

---

## 10. Create Network Load Balancer for API Server

**EC2 → Load Balancers → Create → Network Load Balancer**

- **Name**: `k8s-cluster-dev-api-lb`
- **Scheme**: Internal
- **VPC**: Your VPC
- **Subnets**: Select both private subnets
- **Security groups**: Not applicable (NLB doesn't use SGs)

**Create Target Group:**
- **Name**: `k8s-cluster-dev-api-tg`
- **Protocol**: TCP
- **Port**: 6443
- **VPC**: Your VPC
- **Health check**: TCP on port 6443

**Add Listener:**
- **Protocol**: TCP
- **Port**: 6443
- **Forward to**: `k8s-cluster-dev-api-tg`

---

## 11. Launch Control Plane Instances

**EC2 → Instances → Launch Instance**

**Instance 1:**
- **Name**: `k8s-cluster-dev-control-plane-1`
- **AMI**: Ubuntu Server 22.04 LTS
- **Instance type**: `t3.medium`
- **Key pair**: `k8s-cluster-dev-key`
- **Subnet**: `k8s-cluster-dev-private-subnet-1`
- **Auto-assign public IP**: Disable
- **Security group**: `k8s-cluster-dev-control-plane-sg`
- **IAM instance profile**: `k8s-cluster-dev-control-plane-role`
- **Storage**: 50 GB gp3, encrypted

**Advanced → User data:**
```bash
#!/bin/bash
hostnamectl set-hostname k8s-cluster-dev-control-plane-1
```

**Tags:**
- `Role`: `control-plane`
- `kubernetes.io_cluster_k8s-cluster`: `owned`

**Repeat for Instance 2:**
- **Name**: `k8s-cluster-dev-control-plane-2`
- **Subnet**: `k8s-cluster-dev-private-subnet-2`
- Update hostname in user data

**Register to Target Group:**
- EC2 → Target Groups → Select `k8s-cluster-dev-api-tg`
- Register targets → Add both control plane instances

---

## 12. Launch Worker Instances

**EC2 → Instances → Launch Instance**

**Worker 1:**
- **Name**: `k8s-cluster-dev-worker-1`
- **AMI**: Ubuntu Server 22.04 LTS
- **Instance type**: `t3.medium`
- **Key pair**: `k8s-cluster-dev-key`
- **Subnet**: `k8s-cluster-dev-private-subnet-1`
- **Security group**: `k8s-cluster-dev-worker-sg`
- **IAM instance profile**: `k8s-cluster-dev-worker-role`
- **Storage**: 50 GB gp3, encrypted

**User data:**
```bash
#!/bin/bash
hostnamectl set-hostname k8s-cluster-dev-worker-1
```

**Tags:**
- `Role`: `worker`
- `kubernetes.io_cluster_k8s-cluster`: `owned`

**Repeat for Worker 2:**
- **Name**: `k8s-cluster-dev-worker-2`
- **Subnet**: `k8s-cluster-dev-private-subnet-2`

---

## 13. Verify Infrastructure

### Check Connectivity:

1. **SSH to Bastion:**
   ```bash
   ssh -i k8s-cluster-dev-key.pem ubuntu@<bastion-public-ip>
   ```

2. **From Bastion, SSH to Control Plane:**
   ```bash
   ssh ubuntu@<control-plane-private-ip>
   ```

3. **Verify Internet Access from Private Instances:**
   ```bash
   curl -I https://google.com
   ```

4. **Get Load Balancer DNS:**
   - EC2 → Load Balancers → Copy DNS name
   - Use this as `--control-plane-endpoint` in kubeadm init

---

## Summary

Your infrastructure is now ready:

- ✅ VPC with public and private subnets across 2 AZs
- ✅ Internet Gateway for public subnet
- ✅ NAT Gateways for private subnet internet access
- ✅ Security groups configured for K8s communication
- ✅ Bastion host in public subnet
- ✅ Network Load Balancer for API server HA
- ✅ 2 Control plane nodes in private subnets
- ✅ 2 Worker nodes in private subnets

**Next Steps:**
Follow the Kubernetes setup guide in `k8s-setup/ubuntu-cilium-setup.md` to install and configure Kubernetes on these instances.

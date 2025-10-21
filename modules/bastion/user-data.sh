#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install essential tools
apt-get install -y \
    curl \
    wget \
    vim \
    git \
    htop \
    net-tools \
    jq \
    unzip

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install kubectx and kubens (context and namespace switching)
curl -L https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubectx -o /usr/local/bin/kubectx
curl -L https://github.com/ahmetb/kubectx/releases/download/v0.9.5/kubens -o /usr/local/bin/kubens
chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens

# Install k9s (Kubernetes CLI UI)
curl -sS https://webinstall.dev/k9s | bash
mv ~/.local/bin/k9s /usr/local/bin/

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

%{ if enable_ssm }
# Install SSM Agent (usually pre-installed on Ubuntu 22.04)
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
%{ endif }

# Configure SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Set timezone
timedatectl set-timezone UTC

echo "Bastion host setup complete" > /var/log/user-data.log

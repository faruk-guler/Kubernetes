# 🐄 Install and Configure Kubernetes with RKE2

```console
██████╗ ██╗  ██╗███████╗██████╗     ██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ███╗   ██╗███████╗████████╗███████╗███████╗
██╔══██╗██║ ██╔╝██╔════╝╚════██╗    ██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗████╗  ██║██╔════╝╚══██╔══╝██╔════╝██╔════╝
██████╔╝█████╔╝ █████╗   █████╔╝    █████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██╔██╗ ██║█████╗     ██║   █████╗  ███████╗
██╔══██╗██╔═██╗ ██╔══╝  ██╔═══╝     ██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║╚██╗██║██╔══╝     ██║   ██╔══╝  ╚════██║
██║  ██║██║  ██╗███████╗███████╗    ██║  ██╗╚██████╔╝██████╔╝███████╗██║  ██║██║ ╚████║███████╗   ██║   ███████╗███████║
╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚══════╝╚══════╝
               ,        ,
   ,-----------|'------'| 
  /.           '-'    |-'
 |/|             |    |
   |   .________.'----'
   |  ||        |  ||
   \__|'        \__|'  BY SUSE
      ___             _           _                
     |  _|___ ___ _ _| |_ ___ _ _| |___ ___ 
     |  _| .'|  _| | | '_| . | | | | -_|  _|
WWW .|_| |__,|_| |___|_,_|  _|___|_|___|_|.COM

Name: RKE2 (Rancher Kubernetes Engine 2) Cluster Installation Script.
POC: Debian 12 "Bookworm"
Author: faruk guler
Date: 2025
```
## Introduction:
RKE2 is the enterprise ready,stable and secure kubernetes distribution which is easy to install configure and manage. It is a fully conformant Kubernetes distribution that focuses on security and compliance within the U.S. Federal Government sector. Most of the enterprise configurations comes out of the boxy from the installation like:
- Canal CNI Plugin (Calico + Flannel)
- CoreDNS
- ETCD (embedded)
- Integrated Containerd
- Air-Gapped Support
- FIPS 140-2 compliance
- Tip: For HA, use an odd number of server nodes (3 or 5) and a stable VIP/DNS with tls-san.
- 

## VM Requirements:
```bash
| Name       | CPU | RAM    | IP             | Disk  | OS                       | Role       | Node Type   |
|------------|-----|--------|----------------|-------|--------------------------|------------|-------------|
| master-01  | 4   | 8Gi    | 192.168.1.120  | 100GB | Debian 12 "Bookworm" x64 | master-*   | server      |
| worker-01  | 4   | 8Gi    | 192.168.1.245  | 100GB | Debian 12 "Bookworm" x64 | worker-*   | agent       |
| worker-02  | 4   | 8Gi    | 192.168.1.246  | 100GB | Debian 12 "Bookworm" x64 | worker-*   | agent       |
| worker-03  | 4   | 8Gi    | 192.168.1.247  | 100GB | Debian 12 "Bookworm" x64 | worker-*   | agent       |
----
```

## Other Prerequisites (All Nodes):
``` bash
# General Information
- Hostnames must be unique:
- In general, RKE2 should work on any Linux distribution that uses systemd and iptables.
- Windows Support requires choosing Calico or Flannel as the CNI for the RKE2 cluster
- The Windows Server Containers feature needs to be enabled for the RKE2 Windows agent to work.
- It is always recommended to have an odd number of server nodes.
- Certificates in RKE2 have a default expiration date of 365 days.

- https://docs.rke2.io/install/requirements
- https://docs.rke2.io/architecture

# Load kernel modules:
sudo modprobe br_netfilter
sudo modprobe overlay

# Persistent Kernel modules:
cat <<EOF | sudo tee /etc/modules-load.d/rke2-k8s.conf
overlay
br_netfilter
EOF

# Sysctl conf.
cat <<EOF | sudo tee /etc/sysctl.d/rke2-k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Unique Hostname configuration:
Master Node: sudo hostnamectl set-hostname master-01
Worker Node: sudo hostnamectl set-hostname worker-01
-------

# Simple DNS Integration: "/etc/hosts" file:
cat <<EOF | sudo tee /etc/hosts
192.168.1.120 master-01
192.168.1.245 worker-01
192.168.1.246 worker-02
192.168.1.247 worker-03
EOF

# Disable swap space:
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab # Permanently
sudo mount -a
swapon --show
free -h

# Require packages:
sudo apt update
sudo apt upgrade
sudo apt install -y curl wget gnupg lsb-release apt-transport-https ca-certificates

# NTP Synchronization:
sudo apt install -y chrony
sudo systemctl enable chronyd
sudo systemctl start chronyd
sudo systemctl status chrony
```

## Install Control-Plane/Master Node
``` bash
# Create config file
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

# >> config.yaml file:
node-name: master-01
write-kubeconfig-mode: "0644"
cluster-init: true  # required for HA, only on the first master

# install:
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="v1.28.6+rke2r1" sudo sh - [specific version]
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_CHANNEL="stable" sudo sh -         [specific channel]

# Starting Service and logs:
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
sudo journalctl -u rke2-server -f

# Kubeconfig for kubectl:
mkdir -p $HOME/.kube
sudo cp /etc/rancher/rke2/rke2.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
sudo chmod 600 $HOME/.kube/config

# persistent binaries
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin/' >> ~/.bashrc
source ~/.bashrc

# Get tokens for worker node:
sudo rke2 token create
sudo cat /var/lib/rancher/rke2/server/node-token

# Disable Firewall or Allow Requirements Ports:

**Control Plane Node
- TCP: 6443, 2379-2380, 10250, 10257, 10259
- UDP: 8472 (VXLAN)

Open Ports: https://docs.rke2.io/install/requirements
sudo netstat -tuln | grep -E '6443|9345'

```

## Install Worker/Agent Node
``` bash
# install:
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -

# Create config file:
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

# >> config.yaml file:
node-name: worker-01
server: https://192.168.1.120:9345
token-file: /etc/rancher/rke2/token

# Setting File Permissions:
sudo chmod 600 /etc/rancher/rke2/config.yaml
sudo chmod 600 /etc/rancher/rke2/token
sudo chown root:root /etc/rancher/rke2/config.yaml
sudo chown root:root /etc/rancher/rke2/token

# Starting Service and logs:
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service
sudo journalctl -u rke2-agent -f

# Disable Firewall or Allow Requirements Ports:

**Worker Node**
- TCP: 10250, 30000-32767
- UDP: 8472 (VXLAN)

Open Ports: https://docs.rke2.io/install/requirements
sudo netstat -tuln | grep -E '6443|9345'

```

## RKE2 certificates(365):
``` bash
sudo rke2 certificate rotate
sudo systemctl restart rke2-server # on server nodes
sudo systemctl restart rke2-agent  # on agent nodes
echo "0 0 1 * * root /usr/local/bin/rke2 certificate rotate >> /var/log/rke2/cert-rotate.log 2>&1" | sudo tee /etc/cron.d/rke2-cert-rotate
```

## Verify Installation:
``` bash

# Cluster Status:
kubectl cluster-info
kubectl get componentstatuses

# RKE version:
rke2 --version
rke config --list-version --all

# Check control-plane services:
sudo systemctl status rke2-server --no-pager

# list nodes:
kubectl get nodes -o wide

# kubectl check:
kubectl version

# list services:
sudo systemctl status rke2-server

# check pods:
kubectl get pods -A

# Network connectivity test
curl -k https://192.168.1.120:9345/version

# CNI control:
kubectl get daemonset -n kube-system | grep -i cni

```

Congratulations! 🎉

Thank you for following along. You have successfully installed a Kubernetes cluster using RKE2! 🎉🎉🎉

# Referance
```
https://docs.rke2.io/
https://docs.rke2.io/install/quickstart/
https://docs.rke2.io/install/requirements/
https://docs.rke2.io/architecture/
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

```

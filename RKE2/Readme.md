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
-




```bash
## Bu kritik adımlar eksik:
Kernel modülleri
sudo modprobe br_netfilter
sudo modprobe overlay

## Sysctl conf.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

```


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

## Other Requirements:
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

# Hostname configuration:
Master Node: sudo hostnamectl set-hostname master-01
Worker Node: sudo hostnamectl set-hostname worker-01
-------

# DNS Integration: "/etc/hosts" file:
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
free -h

# Require packages:
sudo apt update
sudo apt upgrade
sudo apt install -y curl wget gnupg lsb-release

# Firewall Requirements and Ports:

**Control Plane Node
- TCP: 6443, 2379-2380, 10250, 10257, 10259
- UDP: 8472 (VXLAN)

**Worker Node**
- TCP: 10250, 30000-32767
- UDP: 8472 (VXLAN)

Open Ports: https://docs.rke2.io/install/requirements
sudo netstat -tuln | grep -E '6443|9345'

# NTP Synchronization:
sudo apt install ntp -y
sudo systemctl enable ntp
sudo systemctl start ntp
sudo timedatectl status
```

## Install Server/Master Node
``` bash
# Before running the install script, create the config file:
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

# config file:
node-name: master-01
write-kubeconfig-mode: "0644"
cluster-init: true  # required for single master HA

# install:
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="server" sh -

# Starting service:
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service

# logs:
journalctl -u rke2-server -f

# copy kubeconfig:
mkdir -p $HOME/.kube
sudo cp /etc/rancher/rke2/rke2.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# persistent binaries
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin/' >> ~/.bashrc
source ~/.bashrc

# Get tokens for worker node:
sudo cat /var/lib/rancher/rke2/server/node-token

```

## Install Worker/Agent Node
``` bash
# install:
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -

# Preparing config file: Creating file
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

# config file: [Master server ip or Hostname]
server: https://<server>:9345
token: <token from master server node>

# quick example:
sudo chmod 600 /etc/rancher/rke2/config.yaml
>> Edit file >> /etc/rancher/rke2/config.yaml
server: https://192.168.1.120:9345
node-name: worker-01
token: <token-from-master-node>

# Starting Service:
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service

# logs:
journalctl -u rke2-agent -f

# Renew RKE2 certificates(365):
sudo rke2 certificate rotate
-----

```

## Verify Installation:
``` bash

# Cluster Status:
kubectl cluster-info
kubectl get componentstatuses

# list nodes:
kubectl get nodes -o wide

# kubectl check:
kubectl version

# list services:
sudo systemctl status rke2-server

# check pods:
kubectl get pods -A
```

Congratulations! 🎉

Thank you for following along. You have successfully installed a Kubernetes cluster using RKE2! 🎉🎉🎉

# Referance
```
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd
https://docs.rke2.io/
https://docs.rke2.io/install/quickstart/
https://docs.rke2.io/install/requirements/
https://docs.rke2.io/architecture/

```

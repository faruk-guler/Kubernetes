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
## VM Requirements:
```bash
| Name       | CPU | RAM    | IP             | Disk  | OS                       |
|------------|-----|--------|----------------|-------|--------------------------|
| master-01  | 4   | 8Gi    | 192.168.1.120  | 100GB | Debian 12 "Bookworm" x64 |
| worker-01  | 4   | 8Gi    | 192.168.1.245  | 100GB | Debian 12 "Bookworm" x64 |
| worker-02  | 4   | 8Gi    | 192.168.1.246  | 100GB | Debian 12 "Bookworm" x64 |
| worker-03  | 4   | 8Gi    | 192.168.1.247  | 100GB | Debian 12 "Bookworm" x64 |
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


# Adding Hostname to "/etc/hosts" file:
echo "192.168.1.120 master-01" | sudo tee -a /etc/hosts
echo "192.168.1.245 worker-01" | sudo tee -a /etc/hosts
echo "192.168.1.246 worker-02" | sudo tee -a /etc/hosts
echo "192.168.1.247 worker-03" | sudo tee -a /etc/hosts

# Disable swap space:
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab [Permanently]
sudo mount -a
free -h

# Require packages:
sudo apt update
sudo apt upgrade
sudo apt install -y curl wget gnupg lsb-release

# Firewall Requirements and Ports: (optional)
sudo ufw disable
sudo systemctl disable firewalld
sudo systemctl disable iptables
sudo systemctl disable nftables

Ports: https://docs.rke2.io/install/requirements

```

## Install Server/Master Node
``` bash
# Before running the install script, create the config file:
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

# config file:
node-name: master-01
write-kubeconfig-mode: "0644"

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
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
server: https://192.168.1.120:9345
node-name: worker-01
token: K10347e1369de4d6b2c4d7195ad6df8738a1d26b458ac997ef99ded44f09c7c7289::server:bed45765f5ef39e91feb99100b83e7ba
EOF

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
# Düğümleri listele:
kubectl get nodes -o wide

# kubectl check:
kubectl version

# Servisi listele:
sudo systemctl status rke2-server

# Pod'ları kontrol et:
kubectl get pods -A
```

Congratulations! 🎉

Thank you for following along. You have successfully installed a Kubernetes cluster using RKE2! 🎉🎉🎉

# Referance
```
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

```

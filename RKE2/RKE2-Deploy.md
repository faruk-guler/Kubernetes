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

Name: Rancher Kubernetes Engine 2 (RKE2) Cluster Installation Script.
POC: Debian 12 "Bookworm"
Author: faruk guler
Date: 2025
# 
```
## Introduction:    
RKE2 is the enterprise ready,stable and secure kubernetes distribution which is easy to install configure and manage. Most of the enterprise configurations comes out of the boxy from the installation like:
- Canal CNI Plugin (Calico + Flannel)
- CoreDNS
- ETCD (embedded
-
-
## VM Prerequisites:
```bash
name	core	memory	ip	disk	os
master-01	4	8Gi	192.168.1.12	100GB	Debian 12 "Bookworm" x64
worker-02	4	8Gi	192.168.1.74	100GB	Debian 12 "Bookworm" x64
worker-03	4	8Gi	192.168.1.247	100GB	Debian 12 "Bookworm" x64
----
```

## Other Prerequisites:
``` bash
# Swap off
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab [Permanently]

# Require packages
sudo apt update
sudo apt install -y curl wget gnupg lsb-release

# Firewall Disable: (optional)
sudo ufw disable
sudo systemctl disable firewalld
sudo systemctl disable iptables
sudo systemctl disable nftables

# Confirm setting is correct
sudo mount -a
free -h

```

## Install Master Node
``` bash
# Before running the install script, create the config file
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

#config file:
node-name: k8s-master-1

# install
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -

# Starting service
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
sudo journalctl -u rke2-server -f

# logs
journalctl -u rke2-server -f

# copy kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/rancher/rke2/rke2.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
sudo chown $(whoami):$(whoami) ~/.kube/config

# Get tokens for worker node
sudo cat /var/lib/rancher/rke2/server/node-token

```

## Install Worker-Node
``` bash
# install
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_TYPE="agent" sh -

# Preparing config file: Creating file
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml

# config file: [Master server ip or Hostname]
server: https://<server>:9345
token: <token from master server node>

# apply
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
server: https://192.168.1.41:9345
node-name: k8s-worker-1
token: K10347e1369de4d6b2c4d7195ad6df8738a1d26b458ac997ef99ded44f09c7c7289::server:bed45765f5ef39e91feb99100b83e7ba
EOF

# Starting Service
sudo systemctl enable rke2-agent.service
sudo systemctl start rke2-agent.service

# logs
journalctl -u rke2-agent -f

```

## Install Kubectl
``` bash
# update
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

# dowland
curl -LO https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"

# validate
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

# install
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
chmod +x kubectl
mkdir -p ~/.local/bin
mv ./kubectl ~/.local/bin/kubectl

# check
kubectl version

```

## Install Containerd
``` bash
# Install required packages
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Add Docker repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Install containerd
sudo apt update
sudo apt install -y containerd.io

# Configure containerd and start service
sudo su -
mkdir -p /etc/containerd
containerd config default>/etc/containerd/config.toml

# restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd


# To use the systemd cgroup driver, set plugins.cri.systemd_cgroup = true 
cat /etc/containerd/config.toml | grep SystemdCgroup
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

```

Congratulations! 🎉

Thank you for following along. You have successfully installed a Kubernetes cluster using RKE2! 🎉🎉🎉

# Referance
```
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

```

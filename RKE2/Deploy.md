# 🐄 Install and configure Kubernetes with RKE2

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
```
## Introduction:    
RKE2 is the enterprise ready,stable and secure kubernetes distribution which is easy to install configure and manage. Most of the enterprise configurations comes out of the boxy from the installation like:
 - Nginx ingress controller
 - Metric-server
 - Canal CNI plugin
 - Core DNS
 - ETCD backup and restore snapshot script
 - 
## VM Prerequisites:
```bash
name	core	memory	ip	disk	os
master-01	4	8Gi	192.168.1.12	100GB	Debian 12 "Bookworm" x64
worker-02	4	8Gi	192.168.1.74	100GB	Debian 12 "Bookworm" x64
worker-03	4	8Gi	192.168.1.247	100GB	Debian 12 "Bookworm" x64
```

## Swap,....
``` bash
# Swap off
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab [Permanently]

# Require package
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
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
node-name: k8s-master-1
EOF

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

# config file: template
sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
server: https://master_IP:Port
token: Node Token
EOF

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

## Install Metric Server
``` bash
# install
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.5.0/components.yaml

# check
kubectl get po -n kube-system
kubectl top po

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

## Install Helm
``` bash
# dowland
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# install
sudo apt-get update
sudo apt-get install -y helm

```

## Creating wildcard ssl with certbot
``` bash
# install certbot on ubuntu
sudo apt update 
sudo apt install -y certbot

# wildcard ssl generate
sudo certbot certonly --manual --preferred-challenges dns -d '*.your_domain.com'
sudo certbot certonly --manual --preferred-challenges dns -d '*.devopskings.com.tr'

```

## Install Rancher with HELM
``` bash
# Create ns
kubectl create namespace cattle-system

# Create Kubernetes TLS Secret with Your Certs
kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert=rancher.crt \
  --key=rancher.key

# check
kubectl get secrets -n cattle-system

# adding repo
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# install
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.devopskings.com.tr \
  --set ingress.tls.source=secret \
  --set replicas=1 \
  --set bootstrapPassword=chBoBQv6T6gB
  
---
helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.devopskings.com.tr \
  --set replicas=1 \
  --set ingress.tls.source=secret \
  --set bootstrapPassword=admin
---
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.example.com \
  --set replicas=2 \
  --set ingress.tls.source=secret \
  --set bootstrapPassword=admin \
  --set affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchExpressions[0].key=app \
  --set affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchExpressions[0].operator=In \
  --set affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchExpressions[0].values[0]=rancher \
  --set affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey=kubernetes.io/hostname \
  --set resources.requests.cpu=500m \
  --set resources.requests.memory=1Gi \
  --set resources.limits.cpu=1 \
  --set resources.limits.memory=2Gi \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=2 \
  --set autoscaling.maxReplicas=5 \
  --set autoscaling.targetCPUUtilizationPercentage=80
---




```


# ☸️ Bonus: Install Helm, Rancher, Longhorn, NeuVector
- Install Helm:
```bash
curl -#L https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```
- Install Rancher:
```bash
# Add Rancher Helm repository
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# Add Jetstack (cert-manager) Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Cert-Manager CRD and Installation
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml

# Install or update cert-manager with Helm
helm upgrade -i cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
kubectl get pods -n cert-manager

# Install Rancher with Helm
helm upgrade -i rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=YourStrongPassword123 \
  --set replicas=1

# Verify a Rancher
kubectl get pod -A
kubectl get pods -n cattle-system --watch
https://rancher.example.com

# For updates:
helm repo update
helm upgrade rancher rancher-latest/rancher --namespace cattle-system
```
- Install Longhorn:
```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade -i longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

- Install NeuVector:
```bash
# helm repo add
helm repo add neuvector https://neuvector.github.io/neuvector-helm/ --force-update

# helm install 
export RANCHER1_IP=192.168.1.12

helm upgrade -i neuvector --namespace cattle-neuvector-system neuvector/core --create-namespace --set manager.svc.type=ClusterIP --set controller.pvc.enabled=true --set controller.pvc.capacity=500Mi --set manager.ingress.enabled=true --set manager.ingress.host=neuvector.$RANCHER1_IP.sslip.io --set manager.ingress.tls=true 

# add for single sign-on
# --set controller.ranchersso.enabled=true --set global.cattle.url=https://rancher.$RANCHER1_IP.sslip.io

# # check
kubectl get pod -n cattle-neuvector-system
```
Congratulations! 🎉

Thank you for following along. You have successfully installed a Kubernetes cluster using RKE2! 🎉🎉🎉

# Referance
```
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd


```

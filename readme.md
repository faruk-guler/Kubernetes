<img src="[gorsel-link](https://www.cloudiqtech.com/wp-content/uploads/brizy/imgs/blog_banner9-925x451x0x0x925x451x1597916615.png)" width="auto">

#Inventory [GULER.COM]
Kubectl:  192.168.44.140
Master:   192.168.44.145
Worker1:  192.168.44.146
Worker2:  192.168.44.147
Worker3:  192.168.44.148

Docs:
https://kubernetes.io/
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://labs.play-with-k8s.com/

Master node: sudo hostnamectl set-hostname master
Node1 worker: sudo hostnamectl set-hostname node1
Node2 worker: sudo hostnamectl set-hostname node2
Node3 worker: sudo hostnamectl set-hostname node3

#Uniq Servers:
lsb_release -a
ip a
sudo cat /sys/class/dmi/id/product_uuid

#Firewall and ports:
firewald
ufw

#SELINUX
$ sudo nano /etc/selinux/config
SELINUX=disabled
$ sudo reboot
$ sestatus

#Swap Areas:
$ cat /proc/swaps
$ swapon --show
$ sudo swapoff -a
$ sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
$ free -m
$ lscpu

---------Installing-------------->>

#Kernel modules aktivating
$ sudo modprobe overlay
$ sudo modprobe br_netfilter

$ cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

$ cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

$ sudo sysctl --system

$ sudo apt update
$ sudo apt install containerd
$ sudo systemctl daemon-reload
$ sudo systemctl enable --now containerd
$ sudo systemctl start containerd
$ sudo mkdir -p /etc/containerd
$ containerd config default | tee /etc/containerd/config.toml
$ sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
$ sudo systemctl restart containerd

#Kubeadm kurulumu:
https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
#apt-mark hold kubelet kubeadm kubectl
#apt-mark unhold kubelet kubeadm kubectl
$ nc 127.0.0.1 6443 -v
$ journalctl -u kubelet
$ journalctl -xfe

#Ports:
6443 -> kubeapi server
10250 -> kubelet server
$ sudo ss -tuln | grep -E "6443|10250"

#kubernetes cluster kurulumu:
$ sudo kubeadm config images pull
$ sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=<ip> --control-plane-endpoint=<ip>
$ sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=192.168.44.145 --control-plane-endpoint=192.168.44.145

#Kubernetes Configuration:
sudo scp /etc/kubernetes/admin.conf root@192.168.44.148:/etc/kubernetes/admin.conf
/etc/kubernetes/admin.conf
~/.kube/config

$ mkdir -p $HOME/.kube
$ sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config

#Calico:
$ #kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
$ #kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
$ #kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml
$ kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
$ kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/custom-resources.yaml

#Taint:
$ kubectl taint nodes --all node-role.kubernetes.io/control-plane-
$ kubectl taint nodes --all node-role.kubernetes.io/master-

#Kubectl Auto-Completion:
$ source <(kubectl completion bash)
$ echo "source <(kubectl completion bash)" >> ~/.bashrc
#kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
#sudo apt-get install bash-completion

#Kubernetes dashboard:
#Rancher
#Headlamp

#Begin >>>
$ kubectl version
$ kubectl cluster-info
$ kubectl get nodes
$ kubernetes get nodes -owide
$ kubectl get cs
$ kubectl get all
$ kubectl get all -A

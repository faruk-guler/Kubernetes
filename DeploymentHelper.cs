##################################################
#Name: Persistent Deployments Preparation
#Version: 1.7
#Author: faruk-guler
##################################################

#Working Directory:
mkdir -p /kubernetes/webs
touch farukguler-com.yaml

#NFS Server Install:
sudo apt update
sudo apt install nfs-kernel-server
sudo apt install nfs-common [Worker Nodes/Client]
sudo systemctl enable nfs-server
sudo exportfs -a

#NFS Server Config:
mkdir -p /nfs/kubedata/farukguler/
chmod -R 755 /nfs/kubedata/*
chown -R nobody:nogroup /nfs/kubedata/*
ls -ld /nfs/kubedata/farukguler-com/

#NFS Server Perm:
sudo nano /etc/exports
Add: /nfs/kubedata *(rw,sync,subtree_check) [no_root_squash > full perm.]
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server

#Pod Manual Mount:
mount master:/nfs/kubedata/farukguler-com /repos
ls -l /repos

#PV and NFS Check:
showmount -e localhost [NFS Server IP]
kubectl get pv -n web-page
kubectl get pvc -n web-page
sudo systemctl status nfs-server
sudo exportfs -v

#Namespaces:
kubectl create namespace web-page
kubectl get namespaces

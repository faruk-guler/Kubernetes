##################################################
Name: Kubernetes Cheatsheet
Author: faruk guler
Date: 2025
##################################################

#Kubernetes Info:
kubectl version
kubectl version --client
kubectl config view
kubectl cluster-info
kubectl get componentstatus
kubectl get nodes

#Kubernetes Helper:
kubectl -h
kubectl create -h
kubectl run -h
kubectl explain deploy.spec

#Image Manager:
sudo ctr image ls
sudo ctr image ls | awk '{print $1}'
sudo ctr image pull docker.io/library/nginx:latest
sudo ctr image pull docker.io/library/debian:12
#sudo ctr image rm rancher:xxx

#Imperativing:
kubectl run debian-sv --image=debian:12 --restart=Never -- /bin/bash -c "sleep infinity" [one pod]
kubectl exec -it debian-sv -- /bin/bash
#kubectl create deployment debian-dep --image=debian:12 -- /bin/bash -c "sleep infinity" [deployment for dcale]
#kubectl scale --replicas=4 deployment/debian-dep [Scale]

#Pod export to internet: [dns file]
kubectl exec -ti nginx-1234567 -- bash
echo "nameserver 1.1.1.1" | tee -a /etc/resolv.conf
apt update
apt install neofetch

#Nodes, Pods, Services, Deployments, More...
kubectl get all -n web-page -o wide
kubectl get pods -A -o wide
kubectl get pods -n web-page -o wide
kubectl get deployments,svc -n web-page
kubectl get pv,pvc -n web-page
kubectl get namespaces
kubectl get services -A -o wide
kubectl get services -n web-page
kubectl get events -n web-page
kubectl get configmap -n web-page
kubectl get secret -n web-page
kubectl describe node worker1
kubectl describe pod nginx-1234567 -n web-page
kubectl logs nginx-1234567 -n web-page
kubectl logs nginx-1234567 -n web-page -c <container-name> [multi containers]

#Scaling:
kubectl scale deployment nginx-deployment --replicas=10 -n web-page

#Kubernetes Networking:
kubectl expose pod <pod_name> --type=LoadBalancer --name=<service_name> -n <namespace> [load balancer]
kubectl expose pod <pod_name> --type=ClusterIP --name=<service_name> -n <namespace> [cluster ip]
kubectl port-forward pod/<pod_name> 8080:80 [port forwarding]
kubectl expose pod <pod_name> --type=NodePort --name=<service_name> -n <namespace> [node port]
kubectl create ingress example-ingress --rule="host=www.farukguler.com, path=/blockchain/*, service=blockchain-service:80" -n web-page [ingress]

#More:
https://kubernetes.io/pt-br/docs/reference/kubectl/cheatsheet/
https://cheatsheets.zip/kubernetes

#Kubernetes:
kubectl version
kubectl version --client
kubectl config view
kubectl cluster-info
kubectl get componentstatuses

#Image Manager:
sudo ctr image ls
sudo ctr image ls | awk '{print $1}'
sudo ctr image pull docker.io/library/nginx:latest
#sudo ctr image rm rancherix

#Interaction:


#Pods-Services-Deployments-Nodes
kubectl get nodes
kubectl get pods -A -o wide
kubectl get pods -n web-page -o wide
kubectl get deployment,svc -n web-page
kubectl get pv,pvc -n web-page
kubectl describe nodes
kubectl describe node worker1
kubectl get namespaces
kubectl get services -A -o wide
kubectl get services -n web-page
kubectl get events -n web-page
kubectl logs nginx-1234567 -n web-page
kubectl logs nginx-1234567 -n web-page -c <container-name>
kubectl get configmap -n web-page
kubectl get secret -n web-page

#Scaling:
kubectl scale deployment nginx-deployment --replicas=10 -n web-page

#Pod export to internet: [dns file]
kubectl exec -ti nginx-1234567 -- bash
echo "nameserver 8.8.8.8" | tee -a /etc/resolv.conf
apt update
apt install nano


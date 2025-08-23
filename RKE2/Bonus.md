# ☸️ Bonus
# Install Helm, Rancher, Longhorn, NeuVector, Metric Server
# Install Helm:
```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
```
# Install Rancher:
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
# Install Longhorn:
```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade -i longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

# Install NeuVector:
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
# Install Metric Server
``` bash
# install
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.5.0/components.yaml

# check
kubectl get po -n kube-system
kubectl top po

```

Congratulations! 🎉

# Kurulum Sonrası Servisler ve Araçlar

Kubernetes cluster'ı kurulduktan sonra, operasyonel verimliliği artırmak ve ek yetenekler (depolama, yönetim, güvenlik) kazandırmak için yüklenen temel servisler.

---

## 4.1 Helm: Paket Yöneticisi

Kubernetes için "apt" veya "yum" neyse, Helm de odur.

```bash
# Helm kurulum scripti
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Doğrulama
helm version
```

---

## 4.2 Rancher: Çoklu Cluster Yönetimi

Rancher, Kubernetes cluster'larını görsel olarak yönetmek ve merkezi bir kontrol paneli oluşturmak için standarttır.

```bash
# Rancher Helm reposunu ekle
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# Cert-manager (SSL yönetimi için zorunludur)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Rancher kurulumu
helm upgrade -i rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=AdminPassword123 \
  --set replicas=1
```

---

## 4.3 Longhorn: Dağıtık Depolama (Storage)

Cluster üzerinde yüksek erişilebilirliğe sahip, blok bazlı depolama çözümü.

```bash
# Longhorn kurulumu
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade -i longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

---

## 4.4 NeuVector: Container Güvenliği

Gerçek zamanlı container tarama, firewall ve ağ güvenliği sağlar.

```bash
# Repo ekleme ve kurulum
helm repo add neuvector https://neuvector.github.io/neuvector-helm/ --force-update

helm upgrade -i neuvector --namespace cattle-neuvector-system neuvector/core \
  --create-namespace \
  --set manager.svc.type=NodePort \
  --set controller.pvc.enabled=true
```

---

## 4.5 Metrics Server: Kaynak İzleme

`kubectl top` komutunun çalışması ve HPA (Auto-scaling) için gereklidir.

```bash
# Metrics Server kurulumu
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Güvensiz (Insecure) TLS hatasını önlemek için (Test ortamı):
# kubectl edit deployment metrics-server -n kube-system
# args kısmına --kubelet-insecure-tls ekleyin.
```

---

## 4.6 Certbot: Wildcard SSL Oluşturma

Sertifika yönetimi (LetsEncrypt) için DNS tabanlı doğrulama.

```bash
# Paket kurulumu
sudo apt update && sudo apt install -y certbot

# Wildcard SSL oluşturma (DNS testi ile)
sudo certbot certonly --manual --preferred-challenges dns -d '*.your-domain.com'
```

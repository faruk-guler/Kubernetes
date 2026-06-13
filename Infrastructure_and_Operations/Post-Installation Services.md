# Kurulum Sonrası Servisler ve Araçlar

Kubernetes cluster'ı kurulduktan sonra, operasyonel verimliliği artırmak ve ek yetenekler (depolama, yönetim, güvenlik) kazandırmak için yüklenen temel servisler.

---

## Helm: Paket Yöneticisi

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

## Rancher: Çoklu Cluster Yönetimi

Rancher, Kubernetes cluster'larını görsel olarak yönetmek ve merkezi bir kontrol paneli oluşturmak için standarttır.

```bash
# Rancher Helm reposunu ekle
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

# Cert-manager (SSL yönetimi için zorunludur — OCI ile)
helm install cert-manager \
  oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true

# Rancher kurulumu
helm upgrade -i rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=AdminPassword123 \
  --set replicas=1
```

---

## Longhorn: Dağıtık Depolama (Storage)

Cluster üzerinde yüksek erişilebilirliğe sahip, blok bazlı depolama çözümü.

```bash
# Longhorn kurulumu
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade -i longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

---

## NeuVector: Container Güvenliği

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

## Metrics Server: Kaynak İzleme

`kubectl top` komutunun çalışması ve HPA (Auto-scaling) için gereklidir.

```bash
# Metrics Server kurulumu
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Güvensiz (Insecure) TLS hatasını önlemek için (Test ortamı):
# kubectl edit deployment metrics-server -n kube-system
# args kısmına --kubelet-insecure-tls ekleyin.
```

---

> [!TIP]
> TLS sertifika yönetimi için `cert-manager` kullanın. Let's Encrypt entegrasyonu, otomatik yenileme ve Gateway API desteği `cert-manager` ile yapılır.

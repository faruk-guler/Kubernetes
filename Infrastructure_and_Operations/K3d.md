# K3d — Docker Tabanlı Hafif Kubernetes Lab Ortamı

K3d, **K3s** (hafif Kubernetes dağıtımı) cluster'larını Docker container'ları içinde çalıştırmanızı sağlayan bir araçtır. Tek komutla çok node'lu cluster oluşturulabilir, CI/CD pipeline'larında ve local geliştirme ortamlarında idealdir.

---

## K3s Nedir?

K3s, Rancher Labs tarafından 2019'da açık kaynak olarak yayımlanan sertifikalı bir Kubernetes dağıtımıdır. 100 MB altında tek bir binary dosyasıdır.

**Sistem Gereksinimleri:**
- Linux kernel 3.10+
- 512 MB RAM (server node)
- 75 MB RAM (agent node)
- 200 MB disk alanı

---

## Kurulum

### Gereksinimler
- Docker (çalışıyor olmalı)
- kubectl
- k3d binary

```bash
# Docker — hızlı kurulum scripti
curl https://releases.rancher.com/install-docker/19.03.sh | sh

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# k3d — resmi kurulum scripti
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Versiyon kontrolü
k3d version
kubectl version --client
```

---

## Temel Komutlar

### Cluster Yönetimi

```bash
# Yeni cluster oluştur
k3d cluster create my-cluster

# Cluster listele
k3d cluster list

# Cluster başlat / durdur
k3d cluster start my-cluster
k3d cluster stop my-cluster

# Cluster sil
k3d cluster delete my-cluster
k3d cluster delete -a          # Tüm cluster'ları sil
```

### Node Yönetimi

```bash
# Node listele
k3d node list

# Node oluştur ve cluster'a ekle
k3d node create new-node --cluster my-cluster --role server

# Node sil
k3d node delete my-node
```

---

## Port Yönlendirme (NodePort Erişimi)

Uzak bir sunucuya kurulumda veya dışarıdan erişim için port aralığı açın:

```bash
# 30000-30100 aralığını dışa aç
k3d cluster create my-cluster -p "30000-30100:30000-30100@server[0]"

# Tek port
k3d cluster create my-cluster -p "8080:80@loadbalancer"
```

```yaml
# NodePort servisi ile kullanım örneği
apiVersion: v1
kind: Service
metadata:
  name: demo-svc
spec:
  selector:
    app: demo
  type: NodePort
  ports:
  - port: 80
    nodePort: 30050
```

```bash
# Tarayıcıda: http://<sunucu-ip>:30050
```

---

## Multi-Node Cluster

```bash
# 3 server node'lu cluster
k3d cluster create prod-sim --servers 3

# 1 server + 3 agent (worker) node
k3d cluster create prod-sim --servers 1 --agents 3

# Çalışırken node ekle
k3d node create extra-node --cluster prod-sim --role agent

# Kontrol et
kubectl get nodes
k3d cluster list
```

---

## LoadBalancer Erişimi

```bash
# LoadBalancer ile cluster oluştur (80 ve 443 portları yönlendir)
k3d cluster create my-cluster \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer"
```

---

## kubeconfig Yönetimi

```bash
# kubeconfig'i otomatik merge et
k3d cluster create my-cluster --kubeconfig-update-default

# Manuel merge
k3d kubeconfig merge my-cluster --kubeconfig-switch-context
kubectl config get-contexts
kubectl config use-context k3d-my-cluster
```

---

## K3d vs Diğer Local Araçlar

| Özellik | K3d | Minikube | KIND |
|---|---|---|---|
| Backend | Docker container | VM / Docker | Docker container |
| Multi-node | ✅ | ⚠️ Sınırlı | ✅ |
| Başlatma hızı | ⚡ Çok hızlı | 🐢 Yavaş | ⚡ Hızlı |
| Kaynak tüketimi | Düşük | Yüksek | Düşük |
| LoadBalancer | ✅ Built-in | ⚠️ Eklenti gerekir | ⚠️ MetalLB gerekir |
| Kullanım alanı | Local + CI/CD | Local dev | Local + CI/CD |

> [!TIP]
> CI/CD pipeline'larında (GitHub Actions, GitLab CI) K3d veya KIND tercih edin. Minikube VM gerektirdiğinden pipeline'larda genellikle sorun çıkarır.

---

## Hızlı Lab Senaryosu

```bash
# 1. Cluster oluştur
k3d cluster create lab --servers 1 --agents 2 -p "8080:80@loadbalancer"

# 2. NGINX deploy et
kubectl create deployment nginx --image=nginx:1.27
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# 3. Erişim testi
curl http://localhost:8080

# 4. Lab bitince temizle
k3d cluster delete lab
```

---

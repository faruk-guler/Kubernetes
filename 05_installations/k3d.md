# K3d ile Docker Üzerinde K3s Laboratuvarı (K3d Guide)

**K3d**, son derece hafif ve sertifikalı bir Kubernetes dağıtımı olan **K3s**'i Docker konteynerleri içerisinde çalıştırmanızı sağlayan açık kaynaklı bir yardımcı araçtır.

Tek bir komutla makinenizde çok düğümlü (multi-node) bir Kubernetes kümesini saniyeler içinde ayağa kaldırabilir. Bu özelliği sayesinde yerel geliştirme süreçlerinde ve CI/CD otomasyon boru hatlarında (GitHub Actions vb.) test ortamı oluşturmak için mükemmel bir araçtır.

---

## 1. K3s Nedir?

K3s, Rancher Labs tarafından özellikle kaynak kısıtı olan Edge (uç cihazlar), IoT ve CI/CD ortamları için tasarlanmış, standart Kubernetes'in gereksiz kodlarının (bulut entegrasyonları, eski depolama sürücüleri vb.) temizlenmesiyle oluşturulmuş tek bir binary dosyasıdır (boyutu 100MB'ın altındadır).

### K3s Sistem Gereksinimleri

* **İşletim Sistemi:** Linux kernel 3.10+
* **Sunucu Bellek (Master/Server):** Minimum 512 MB RAM
* **Ajan Bellek (Worker/Agent):** Minimum 75 MB RAM
* **Disk:** Minimum 200 MB disk alanı

---

## 2. K3d Kurulumu

K3d kullanabilmek için bilgisayarınızda **Docker** ve **kubectl** araçlarının kurulu ve çalışır durumda olması gerekir.

```bash
# Linux / macOS üzerinde k3d kurulum scripti
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Kurulum doğrulama
k3d version
kubectl version --client
```

---

## 3. Küme (Cluster) Yönetimi Temel Komutları

```bash
# 1. 'my-cluster' adında varsayılan tek düğümlü bir küme oluşturma
k3d cluster create my-cluster

# 2. Çalışan tüm k3d kümelerini listeleme
k3d cluster list

# 3. Kümeyi geçici olarak durdurma ve başlatma
k3d cluster stop my-cluster
k3d cluster start my-cluster

# 4. Kümeyi tamamen silme
k3d cluster delete my-cluster

# 5. Tüm k3d kümelerini topluca silme
k3d cluster delete -a
```

---

## 4. Çok Düğümlü (Multi-Node) Küme Kurulumu

K3d ile birden fazla master (server) ve worker (agent) düğümü barındıran kompleks yapıları simüle etmek oldukça kolaydır:

```bash
# 1 Master ve 3 Worker düğümden oluşan küme oluşturma
k3d cluster create prod-sim --servers 1 --agents 3

# Çalışma anında mevcut kümeye yeni bir worker düğümü ekleme
k3d node create extra-node --cluster prod-sim --role agent

# Düğümleri sorgulama
kubectl get nodes
```

---

## 5. Port Yönlendirme ve LoadBalancer Erişimi

K3d, konteyner içinde çalıştığından, dış dünyadan podlara doğrudan erişemezsiniz. Erişim sağlamak için port yönlendirme yapılmalıdır:

### Ingress / LoadBalancer İçin HTTP/HTTPS Yönlendirmesi

```bash
# 80 ve 443 portlarını yerel makineye yönlendirerek küme oluşturma
k3d cluster create web-cluster \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer"
```

### NodePort Servisleri İçin Port Aralığı Açma

```bash
# NodePort aralığını yerel makineye yönlendirme
k3d cluster create nodeport-cluster -p "30000-30100:30000-30100@server:0"
```

---

## 6. Kubeconfig Yönetimi

K3d, yeni bir küme oluşturduğunda varsayılan `~/.kube/config` dosyanızı otomatik olarak günceller ve context'i yeni kümeye geçirir.

```bash
# Kümeyi kurarken kubeconfig'i otomatik birleştir (merge)
k3d cluster create my-cluster --kubeconfig-update-default

# Manuel olarak kubeconfig context'ini değiştirme
kubectl config get-contexts
kubectl config use-context k3d-my-cluster
```

---

## 7. K3d vs. KIND vs. Minikube Karşılaştırması

| Özellik | K3d | KIND (Kubernetes in Docker) | Minikube |
|:---|:---:|:---:|:---:|
| **Altyapı (Backend)** | Docker (K3s tabanlı) | Docker (Vanilla K8s) | Sanal Makine (VM) / Docker |
| **Açılış Hızı** | ⚡ Ultra Hızlı (< 15 sn) | ⚡ Hızlı (< 30 sn) | 🐢 Yavaş (> 2 dk) |
| **Kaynak Tüketimi** | 🟢 Çok Düşük | 🟢 Düşük | 🔴 Yüksek |
| **Yerleşik LoadBalancer**| ✅ Evet (Traefik hazır gelir) | ❌ Hayır (MetalLB gerekir) | 🟡 Kısmen (`minikube tunnel`) |
| **CI/CD Pipeline Uyumu**| ✅ Mükemmel | ✅ Mükemmel | ❌ Zor (VM desteği kısıtlıdır) |

---

## 8. Hızlı Laboratuvar Senaryosu (Lab Runbook)

Makinenizde hızlıca bir web uygulamasını deploy edip test etmek ve temizlemek için şu adımları izleyin:

```bash
# 1. 8080 portunu dışarı açarak 2 worker'lı bir küme kurun
k3d cluster create lab-cluster --servers 1 --agents 2 -p "8080:80@loadbalancer"

# 2. Örnek NGINX uygulamasını deploy edin
kubectl create deployment nginx-web --image=nginx:1.25

# 3. Uygulamayı LoadBalancer servisi ile dışarı açın
kubectl expose deployment nginx-web --port=80 --type=LoadBalancer

# 4. Tarayıcınızdan veya curl ile test edin
curl http://localhost:8080

# 5. Laboratuvarı sonlandırıp tüm kaynakları temizleyin
k3d cluster delete lab-cluster
```

---

## Özet

K3d, yerel bilgisayarınızda kurumsal Kubernetes mimarilerini (yük dengeleme, çoklu düğüm, ingress) minimum kaynak tüketimiyle simüle etmenin en pratik yoludur. **K3s**'in hafif yapısı ve **Docker**'ın hızı birleştiğinde, test ve geliştirme süreçlerinizi saatlerden saniyelere indirir.

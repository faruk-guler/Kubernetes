# Yerel Geliştirme Ortamları (Local Dev)

Kubernetes öğrenmek, uygulama test etmek veya CI/CD boru hatlarında hafif kümeler kullanmak için tam teşekküllü bir bulut ortamına ihtiyacınız yoktur. Yerel bilgisayarınızda saniyeler içinde çalışan çözümler mevcuttur.

---

## 🚀 Popüler Yerel Çözümler Karşılaştırması

| Araç | Çalışma Biçimi | En İyi Kullanım Senaryosu | Kaynak Tüketimi |
|:---|:---|:---|:---|
| **minikube** | VM veya Docker | Standart öğrenme, tüm eklentiler (addons) | Orta/Yüksek |
| **kind** | Docker-in-Docker | CI/CD, hızlı testler, multi-node | Düşük |
| **k3d (k3s)** | Docker | Lightweight, IoT ve Edge simülasyonu | Çok Düşük |
| **OrbStack** | Native (Mac) | macOS için en hızlı ve hafif çözüm | Çok Düşük |
| **Colima** | VM (Linux/Mac) | Docker Desktop alternatifi, açık kaynak | Düşük |

---

## 1. minikube: Klasik ve Kapsamlı

Minikube, Kubernetes'i bir sanal makine veya Docker konteyneri içinde çalıştırır. Zengin eklenti (addon) kütüphanesi ile bilinir.

```bash
# Kurulum (macOS)
brew install minikube

# Cluster başlatma
minikube start --driver=docker --cpus=4 --memory=4096

# Eklenti yönetimi (örneğin Ingress)
minikube addons enable ingress

# Dashboard erişimi
minikube dashboard
```

---

## 2. kind (Kubernetes in Docker)

Kind, Kubernetes node'larını Docker konteynerleri olarak çalıştırır. Özellikle çoklu node (multi-node) testleri için idealdir.

```bash
# Cluster oluşturma
kind create cluster --name test-cluster

# Multi-node yapılandırma (config.yaml)
# kind create cluster --config config.yaml
```

---

## 3. k3d: En Hafifi

K3d, Rancher'ın ultra-hafif K8s dağıtımı olan **k3s**'i Docker üzerinde çalıştırır. Kaynak tüketimi en düşük olanıdır.

```bash
# Cluster oluşturma ve port yönlendirme
k3d cluster create my-cluster -p "8080:80@loadbalancer"

# Node ekleme
k3d node create new-worker --cluster my-cluster --role agent
```

---

## 4. 2026 Modern Alternatifleri

### OrbStack (macOS)
Docker Desktop'a göre 10 kat daha hızlı başlayan, ağ ve disk performansı native'e yakın olan bir araçtır. Tek bir tıkla Kubernetes cluster'ını aktif hale getirir.

### Colima
Docker Desktop gerektirmeden, Lima üzerinden Linux sanal makineleri yaratarak Kubernetes çalıştırır. Tamamen açık kaynaklıdır.

---

## 💡 Hangi Aracı Seçmeliyim?

- **Mac kullanıcısıyım, hız istiyorum:** OrbStack.
- **Her şeyi öğrenmek istiyorum:** minikube.
- **CI/CD boru hattı yazıyorum:** kind.
- **Eski donanımım var, çok kısıtlıyım:** k3d.

---
*← [etcd Yedekleme](05_etcd_yedekleme.md) | [Ana Sayfa](../README.md)*

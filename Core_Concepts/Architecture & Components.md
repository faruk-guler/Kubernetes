# Kubernetes Mimarisi ve Bileşenleri

## Control Plane Bileşenleri

Control Plane, cluster'ın karar verme merkezidir. Üretim ortamlarında **yüksek erişilebilirlik (HA)** için en az 3 Control Plane node'u kullanılır.

### kube-apiserver (API Server)
- **Kubernetes'in Beyni:** Cluster'ın merkezi yönetim noktasıdır. Tüm `kubectl` komutları ve iç bileşen iletişimleri bu REST API üzerinden gerçekleşir.
- Kimlik doğrulama (Authentication), yetkilendirme (Authorization) ve mutasyon/validasyon işlemlerini yürütür.
- Cluster içindeki tüm değişiklikler API Server üzerinden geçer.

### etcd
- **Cluster Hafızası:** Cluster'ın tüm durumunu (desired state) saklayan dağıtık ve tutarlı bir key-value veritabanıdır.
- **Kritik:** etcd'nin yedeği = cluster'ın yedeği. Tüm konfigürasyon ve kaynak bilgileri burada tutulur.
- Raft konsensüs algoritması kullanır; bu yüzden yüksek erişilebilirlik için **tek sayılı node** (3 veya 5) gerektirir.

### kube-scheduler
- **Zamanlayıcı:** Yeni oluşturulan Pod'ların hangi node üzerinde çalıştırılacağına karar verir.
- **Çalışma Algoritması (İki Aşama):**
    1.  **Filtering (Predicates):** Pod'un kaynak gereksinimlerini karşılamayan (yetersiz RAM/CPU vb.) node'ları eler.
    2.  **Scoring (Priorities):** Kalan node'lar arasında bir puanlama yapar. En yüksek puanı alan (Örn: En az yüklü veya en hızlı diskli) node seçilir.
- Karar verirken affinity/anti-affinity kurallarını, taint/toleration'ları ve node doluluk oranlarını hesaplar.

### kube-controller-manager
- **Kontrol Döngüleri:** Cluster içindeki çeşitli kontrolörleri (reconciliation loops) tek bir process içinde çalıştırır.
- **"Desired State" (Beklenen Durum) vs "Current State" (Mevcut Durum):** Controller'ın ana görevi, cluster'ın durumunu sürekli izleyip beklenen duruma (YAML'da belirttiğimiz) çekmektir.
- **Temel Kontrolörler:**
    - **Node Controller:** Node'ların erişilebilirlik durumunu izler; node düşerse pod'ları tahliye eder.
    - **Replication Controller:** ReplicaSet sayısını denetler; eksikse yeni pod başlatır, fazlaysa kapatır.
    - **Endpoints Controller:** Service ve Pod objelerini ilişkilendirir (Endpoint günceller).
    - **Namespace Controller:** Namespace silindiğinde içindeki tüm kaynakları temizler.

### cloud-controller-manager
- Bulut sağlayıcıya özgü işlemleri (Cloud Load Balancer, Disk ekleme/çıkarma, Node lifecycle) yöneterek Kubernetes'in bulut servisleriyle entegre çalışmasını sağlar.

## Worker Node Bileşenleri

### kubelet
- Her node'da çalışan, node'u API Server'a bağlayan ajandır
- Pod'ların çalışıp çalışmadığını kontrol eder; çöken pod'ları yeniden başlatır

### Container Runtime (Containerd)
- Pod'ların içindeki konteynerleri fiilen çalıştıran motordur
- 2026 standardı: `containerd` (Docker artık doğrudan kullanılmaz)
- CRI (Container Runtime Interface) üzerinden haberleşir

### kube-proxy (2026'da Cilium ile Değiştirildi)
> [!WARNING]
> 2026 standartlarında `kube-proxy` **Cilium eBPF** ile tamamen değiştirilmektedir. `kubeadm init --skip-phases=addon/kube-proxy` ile devredışı bırakılıp Cilium kurulur.

### Cilium (eBPF CNI - 2026 Standardı)
- Linux çekirdeğinde çalışarak ağ yönetimini `iptables`'dan çok daha verimli yapar
- Network Policy, Load Balancing, Egress, Service Mesh yetenekleri tek çatı altında
- **Hubble** UI ile ağ trafiği görselleştirilir

## Bileşen İletişim Diyagramı

```
kubectl / API Client
        │
        ▼
┌──────────────────┐
│   kube-apiserver │◄─── etcd (durumu okur/yazar)
└──────┬───────────┘
       │
   ┌───┐────────────────────────┐
   │                            │
   ▼                            ▼
kube-scheduler          kube-controller-manager
(Pod'u hangi Node?)     (ReplicaSet, Node vb. döngüler)
   │
   ▼ (API üzerinden)
kubelet (Worker Node'da)
   │
   ▼
containerd → Container (Pod)
```

## Namespace

Namespace, cluster kaynaklarını mantıksal olarak gruplandırır. Varsayılan namespace'ler:

| Namespace | Amacı |
|:---|:---|
| `default` | Kullanıcı uygulamaları (namespace belirtilmezse) |
| `kube-system` | Sistem bileşenleri (DNS, scheduler vb.) |
| `kube-public` | Herkese açık kaynaklar |
| `kube-node-lease` | Node heartbeat'leri |

```bash
# Namespace listesi
kubectl get namespaces

# Belirli namespace'de çalışma
kubectl get pods -n kube-system

# Yeni namespace oluşturma
kubectl create namespace my-app
```

> [!TIP]
> Production ortamında her ekip veya uygulama için ayrı namespace kullanın. `ResourceQuota` ve `LimitRange` ile her namespace'e kaynak sınırı atayabilirsiniz.

---

## Static Pods

Static pod'lar, API Server'dan bağımsız olarak doğrudan **kubelet** tarafından yönetilen pod'lardır. Kubernetes'in kendi kontrol düzlemi bileşenleri (etcd, API Server, Scheduler, Controller Manager) bu şekilde çalışır.

```
/etc/kubernetes/manifests/
├── etcd.yaml
├── kube-apiserver.yaml
├── kube-controller-manager.yaml
└── kube-scheduler.yaml
```

```bash
# Kubelet bu dizini izler — dosya eklenince pod otomatik başlar
ls /etc/kubernetes/manifests/

# Static pod'lar kubectl'de mirror object olarak görünür
kubectl get pods -n kube-system
# kube-apiserver-master   1/1  Running  ← Static Pod!

# Silmek için manifest dosyasını kaldır (kubectl delete işe yaramaz)
sudo rm /etc/kubernetes/manifests/my-static-pod.yaml

# API Server çöktüğünde crictl ile debug et
sudo crictl ps -a
sudo crictl logs <container-id>
```

| | Static Pod | DaemonSet |
|---|---|---|
| Yönetim | Kubelet (doğrudan) | API Server |
| API Server gerekli? | ❌ | ✅ |
| kubectl yönetimi | ❌ Sadece görüntüleme | ✅ Tam CRUD |
| Kullanım amacı | Kontrol düzlemi | Monitoring/log agent |

# Resource Management Deep Dive

Kubernetes kaynak yönetimi, cluster'ın sağlıklı çalışmasının ve adil kaynak paylaşımının temelidir. Yanlış yapılandırma hem performans sorunlarına hem de güvenlik açıklarına yol açar.

---

## QoS Sınıfları (Quality of Service)

Kubernetes her pod'u kaynak tanımına göre üç QoS sınıfına atar. Kaynak baskısı anında hangi pod'ların önce öldürüleceğini belirler.

### 1. Guaranteed (En Yüksek Koruma)

```yaml
# Kural: Her container için requests == limits (CPU ve memory ikisi de)
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "500m"
        memory: "256Mi"
      limits:
        cpu: "500m"      # requests ile aynı
        memory: "256Mi"  # requests ile aynı
```

- **OOM Kill önceliği:** En son
- **CPU throttling:** Limit aşılırsa throttle edilir ama öldürülmez
- **Kimler için:** Kritik production servisleri, veritabanları

### 2. Burstable (Orta Koruma)

```yaml
# Kural: En az bir container'da request var ama limits != requests
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "200m"
        memory: "128Mi"
      limits:
        cpu: "1"         # requests'ten büyük
        memory: "512Mi"  # requests'ten büyük
```

- **OOM Kill önceliği:** Orta — kullanım requestlerini aşınca hedef
- **Kimler için:** Çoğu uygulama

### 3. BestEffort (En Düşük Koruma)

```yaml
# Kural: Hiç resources tanımlanmamış
spec:
  containers:
  - name: app
    image: nginx
    # resources: yok
```

- **OOM Kill önceliği:** İlk öldürülenler
- **Kimler için:** Batch iş yükleri, test pod'ları
- **Uyarı:** Production'da asla kullanmayın

### QoS Kontrolü

```bash
kubectl get pod <pod> -o jsonpath='{.status.qosClass}'
# Guaranteed / Burstable / BestEffort
```

---

## LimitRange — Namespace Varsayılanları

Her pod için tek tek limit yazmak yorucu. LimitRange ile namespace seviyesinde varsayılanlar atanır.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
  # Container başına sınırlar
  - type: Container
    default:              # limits belirtilmezse bu değerler kullanılır
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:       # requests belirtilmezse bu değerler kullanılır
      cpu: "100m"
      memory: "64Mi"
    min:                  # Hiçbir container bundan az istemez
      cpu: "50m"
      memory: "32Mi"
    max:                  # Hiçbir container bundan fazla isteyemez
      cpu: "4"
      memory: "4Gi"

  # Pod başına toplam sınır
  - type: Pod
    max:
      cpu: "8"
      memory: "16Gi"

  # PVC başına depolama sınırı
  - type: PersistentVolumeClaim
    max:
      storage: "100Gi"
    min:
      storage: "1Gi"
```

```bash
# LimitRange kontrolü
kubectl describe limitrange default-limits -n production
kubectl describe pod <pod> -n production | grep -A 10 "Limits\|Requests"
```

---

## ResourceQuota — Namespace Toplam Kotası

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-alpha
spec:
  hard:
    # Hesaplama kaynakları
    requests.cpu: "20"
    requests.memory: "40Gi"
    limits.cpu: "40"
    limits.memory: "80Gi"

    # Depolama
    requests.storage: "500Gi"
    persistentvolumeclaims: "20"
    # Belirli StorageClass kısıtı
    longhorn.storageclass.storage.k8s.io/requests.storage: "200Gi"

    # Nesne sayıları
    pods: "100"
    services: "30"
    secrets: "50"
    configmaps: "50"
    services.loadbalancers: "3"
    services.nodeports: "0"          # NodePort yasak

    # QoS sınıfı kısıtı (yalnızca Guaranteed pod'lara izin ver)
    # count/pods.guaranteed: "50"
```

```bash
# Quota kullanımını izle
kubectl describe resourcequota team-quota -n team-alpha
# Name:                    team-quota
# Resource                 Used    Hard
# --------                 ----    ----
# limits.cpu               8       40
# limits.memory            16Gi    80Gi
# pods                     23      100
# requests.cpu             4       20
```

---

## PriorityClass & Preemption

```yaml
# Kritik sistem pod'ları
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: system-critical
value: 2000000000   # Maksimum — Kubernetes'in kendi bileşenleri seviyesi
globalDefault: false
preemptionPolicy: PreemptLowerPriority

---
# Production iş yükleri
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
preemptionPolicy: PreemptLowerPriority
description: "Production kritik servisler"

---
# Batch/test iş yükleri
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
preemptionPolicy: Never    # Başkasını tahliye etmez
description: "Batch ve test iş yükleri"
```

---

## CPU Throttling ve Limit Tasarımı

```bash
# CPU throttle oranını ölç
# 1.0 = %100 throttle, 0.0 = throttle yok
rate(container_cpu_throttled_seconds_total[5m]) /
rate(container_cpu_usage_seconds_total[5m])

# Yüksek throttle → limits çok dar
# Çözüm: limits artır veya uygulama profili çıkar
```

> [!WARNING]
> CPU limits kontrolde tartışmalıdır. Bazı ekipler CPU limits'i tamamen kaldırır — throttling önlemek için. Ancak bu, noisy neighbor sorununa yol açabilir. Altın kural: **CPU requests her zaman ayarla, limits için dikkatli ol**.

---

## Ephemeral Storage Yönetimi

```yaml
# Container log ve geçici dosyaları için sınır
spec:
  containers:
  - name: app
    resources:
      requests:
        ephemeral-storage: "1Gi"
      limits:
        ephemeral-storage: "2Gi"    # Aşarsa pod tahliye edilir
```

---

## Node Kaynak Rezervasyonu

```yaml
# kubelet yapılandırması (/var/lib/kubelet/config.yaml)
kubeReserved:
  cpu: "500m"        # Kubernetes bileşenleri için ayrılan CPU
  memory: "512Mi"    # Kubernetes bileşenleri için ayrılan bellek
systemReserved:
  cpu: "500m"        # OS için ayrılan CPU
  memory: "512Mi"    # OS için ayrılan bellek
evictionHard:
  memory.available: "200Mi"
  nodefs.available: "10%"
  imagefs.available: "15%"
```

```bash
# Node'un gerçek allocatable kaynakları
kubectl describe node <node> | grep -A 10 "Allocatable:"
# Allocatable:
#   cpu:    3500m     # 4 core - 500m kubeReserved
#   memory: 14.5Gi   # 16Gi - 512Mi kubeReserved - 512Mi systemReserved
```

---

## Kaynak Yönetimi En İyi Pratikler

```yaml
# ✅ DOĞRU: Tüm container'lar için requests ve limits
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# ❌ YANLIŞ: Limits yok (BestEffort → ilk öldürülen)
resources:
  requests:
    cpu: "100m"

# ❌ YANLIŞ: Çok yüksek requests (node allocatable'ı aşar → Pending)
resources:
  requests:
    cpu: "32"
    memory: "128Gi"

# ✅ DOĞRU: Kademeli artış — önce VPA ile ölç
# kubectl describe vpa my-app | grep "Target:"
# Target: cpu: 250m, memory: 200Mi
# Bu değerleri requests olarak kullan
```

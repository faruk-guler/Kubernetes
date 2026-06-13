# Performance & Capacity Planning

Kubernetes cluster'ı gereğinden küçük tasarlamak performans sorunlarına, gereğinden büyük tasarlamak ise gereksiz maliyete yol açar. Bu bölüm, doğru boyutlandırmayı ve performans optimizasyonunu sistematik biçimde ele alır.

---

## Cluster Boyutlandırma Metodolojisi

### 1. İş Yükü Profili Çıkar

```bash
# Mevcut cluster'da gerçek kullanımı ölç (en az 2 hafta)
kubectl top nodes
kubectl top pods -A --sort-by=cpu | head -30
kubectl top pods -A --sort-by=memory | head -30

# VPA tavsiyelerini gör (VPA kuruluysa)
kubectl describe vpa -A | grep -A5 "Recommendation"

# PromQL ile uzun dönem analiz
# Son 2 haftanın P95 CPU kullanımı
quantile_over_time(0.95,
  sum(rate(container_cpu_usage_seconds_total{container!=""}[5m]))[14d:5m]
)
```

### 2. Node Boyutu Seçimi

```
Genel Kural:
  Node CPU   = Tüm pod'ların toplam CPU request × 1.3 marj / node sayısı
  Node RAM   = Tüm pod'ların toplam memory request × 1.3 marj / node sayısı

Örnek hesap:
  100 pod × ortalama 200m CPU request = 20 CPU toplam
  20 CPU × 1.3 marj = 26 CPU
  3 node için: her node 9 CPU (10 CPU = m5.2xlarge)

DaemonSet overhead ekle:
  Her node'da ~500m CPU, ~1GB RAM DaemonSet'ler için ayrıla
  (Cilium, node-exporter, fluentbit, etc.)
```

### 3. Node Havuzu Stratejisi

```yaml
# Farklı iş yükleri için farklı node havuzları
Node Pool 1: General Purpose (m5.2xlarge)
  → Stateless web uygulamaları, API'ler

Node Pool 2: Memory Optimized (r5.4xlarge)
  → Elasticsearch, Redis, büyük JVM uygulamaları
  taint: workload=memory-intensive:NoSchedule

Node Pool 3: GPU (g4dn.xlarge)
  → ML training, inference
  taint: nvidia.com/gpu=present:NoSchedule

Node Pool 4: Spot/Preemptible (m5.large)
  → Batch işler, CI/CD job'lar
  taint: spot=true:NoSchedule
```

---

## etcd Performans Optimizasyonu

etcd cluster'ın kalbidir; yavaş etcd her şeyi yavaşlatır.

```bash
# etcd gecikme testi
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  check perf

# Disk fsync gecikmesi (kritik metrik — < 10ms olmalı)
histogram_quantile(0.99,
  rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])
) * 1000

# etcd veritabanı boyutu
etcd_mvcc_db_total_size_in_bytes / 1024 / 1024   # MB cinsinden
```

### etcd Optimizasyon Adımları

```yaml
# /etc/kubernetes/manifests/etcd.yaml — önemli flag'ler
command:
  - etcd
  - --auto-compaction-retention=1     # 1 saatte bir compaction
  - --auto-compaction-mode=periodic
  - --quota-backend-bytes=8589934592  # 8GB max DB boyutu
  - --snapshot-count=5000             # 5000 işlemde snapshot
  - --heartbeat-interval=100          # ms (varsayılan 100)
  - --election-timeout=1000           # ms (varsayılan 1000)
```

```bash
# Manuel compaction (DB şişmişse)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 ... \
  compact $(etcdctl endpoint status --write-out=json | \
    jq '.[0].Status.header.revision')

# Defrag (compaction sonrası boşaltılan alanı geri al)
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 ... defrag
```

> [!WARNING]
> etcd için **NVMe SSD** zorunludur. HDD veya network disk (NFS, bazı cloud instance'ları) kabul edilemez gecikme yaratır.

---

## API Server Performansı

```bash
# API Server istek gecikmesi (P99)
histogram_quantile(0.99,
  rate(apiserver_request_duration_seconds_bucket{verb!="WATCH"}[5m])
)

# API Server istek hacmi
rate(apiserver_request_total[5m])

# Hata oranı
rate(apiserver_request_total{code=~"5.."}[5m]) /
rate(apiserver_request_total[5m])
```

### API Server Ayarları

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
command:
  - kube-apiserver
  - --max-requests-inflight=400         # Paralel istek limiti (varsayılan 400)
  - --max-mutating-requests-inflight=200
  - --watch-cache-sizes=node#500,pod#1000  # Watch cache boyutları
  - --default-watch-cache-size=100
  - --enable-priority-and-fairness=true   # APF — öncelikli istek yönetimi
```

---

## Node Kernel Ayarları

```bash
# /etc/sysctl.d/99-kubernetes.conf
# TCP bağlantı havuzu
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8192

# Dosya descriptor limitleri
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# VM ayarları
vm.swappiness = 0           # Kubernetes swap istemez
vm.overcommit_memory = 1    # Memory overcommit

# Uygula
sysctl -p /etc/sysctl.d/99-kubernetes.conf
```

---

## Load Testing: k6 on Kubernetes

```yaml
# k6 Job ile yük testi
apiVersion: batch/v1
kind: Job
metadata:
  name: load-test-v1
spec:
  template:
    spec:
      containers:
      - name: k6
        image: grafana/k6:0.52.0
        command: ["k6", "run", "/scripts/test.js",
                  "--vus", "100",
                  "--duration", "5m",
                  "--out", "influxdb=http://influxdb:8086/k6"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: k6-scripts
      restartPolicy: Never
```

```javascript
// k6 test scripti (ConfigMap'e koy)
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 50 },   // Ramp up
    { duration: '3m', target: 100 },  // Sustained load
    { duration: '1m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(99)<500'],  // P99 < 500ms
    http_req_failed: ['rate<0.01'],    // Hata oranı < %1
  },
};

export default function () {
  const res = http.get('http://my-service.production.svc.cluster.local/api/orders');
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.1);
}
```

---

## Kapasite Planlama Spreadsheet

```
Hesaplama Şablonu:

Mevcut kullanım (P95, 2 haftalık):
  CPU request toplamı   : _____ core
  Memory request toplamı: _____ GB

Büyüme tahmini (6 ay):
  Yeni servis sayısı    : _____
  Tahmini ek CPU        : _____ core
  Tahmini ek memory     : _____ GB

Hedef (6 ay sonrası):
  Toplam CPU ihtiyacı   : _____ core
  Toplam memory ihtiyacı: _____ GB

Node hesabı:
  Node CPU kapasitesi   : _____ core (allocatable)
  Node memory kapasitesi: _____ GB (allocatable)
  Min node sayısı       : toplam_CPU / node_CPU (yuvarlayıp +1)
  HA için min node      : 3 (control plane) + N worker

Maliyet tahmini:
  Node tipi × sayısı × aylık fiyat = $____/ay
```

---

## Performans Gözlem Kontrol Listesi

```bash
# Haftalık kontrol
□ kubectl top nodes → node CPU/memory %70 altında mı?
□ etcd disk fsync P99 < 10ms mı?
□ API server hata oranı < %0.1 mi?
□ Pod restart sayısı artmış mı? (CrashLoop riski)
□ PVC doluluk oranı < %80 mi?

# Aylık kontrol
□ VPA tavsiyelerini gözden geçir
□ Atıl/over-provisioned node var mı? (Kubecost)
□ etcd DB boyutu < 4GB mı? (compaction gerekiyor mu?)
□ Sertifika son kullanma tarihleri kontrol (kubeadm certs check-expiration)
```

# Küme Performansı, Kapasite Planlama ve FinOps

Kubernetes kümelerini gereğinden küçük tasarlamak darboğazlara ve çökmelere, gereğinden büyük tasarlamak ise bütçenin israf edilmesine yol açar. Bu bölümde, kümenizin kapasitesini nasıl planlayacağınızı, etcd ve Linux çekirdeği düzeyinde performansı nasıl optimize edeceğinizi ve **FinOps** prensipleri çerçevesinde bulut faturalarınızı nasıl kontrol altında tutacağınızı (Kubecost) ele alacağız.

---

## 1. Kapasite Planlama Metodolojisi

Doğru kaynak boyutlandırması yapmak için aşağıdaki adımlar takip edilmelidir:

### Adım 1: İş Yükü Profili Çıkarma

Mevcut çalışan uygulamalarınızın kaynak kullanımını uzun vadeli analiz edin. Prometheus üzerinden son iki haftanın P95 (yüzde 95'lik) kaynak kullanımını ölçmek için şu PromQL sorgusu kullanılır:

```promql
# Son 2 haftanın P95 gerçek CPU kullanımı
quantile_over_time(0.95, sum(rate(container_cpu_usage_seconds_total{container!=""}[5m]))[14d:5m])
```

### Adım 2: Sunucu (Node) Boyutlandırma Stratejisi

* **Küçük Sunucular (Örn: 4 CPU, 8GB RAM) × 20 Düğüm:**
  * *Artı:* Bir sunucu çöktüğünde blast radius (etki alanı) küçüktür, pod yerleşimi esnektir.
  * *Eksi:* Yönetim yükü fazladır; her sunucuda ayrı ayrı çalışan DaemonSet podları (Cilium, Fluent Bit vb.) sistem kaynaklarını (overhead) tüketir.
* **Büyük Sunucular (Örn: 64 CPU, 256GB RAM) × 3 Düğüm:**
  * *Artı:* Yönetimi kolaydır, DaemonSet overhead'i düşüktür.
  * *Eksi:* Bir sunucu çöktüğünde kapasitenizin 1/3'ünü bir anda kaybedersiniz; pod yerleşimi verimsiz olabilir.
* **Altın Kural:** Üretim ortamları için dengeli orta boy sunucular (**16-32 CPU, 64-128GB RAM**) ve kapasite hesaplanırken **%30 yedek (headroom) marjı** bırakılması önerilir.

---

## 2. etcd Performans Optimizasyonu

Kubernetes'in durum hafızası olan `etcd`, disk gecikmelerine karşı aşırı duyarlıdır. etcd'nin yavaşlaması tüm kümede komutların donmasına yol açar.

### Performans Teşhisi

etcd düğümlerinin disk yazma performansını test etmek için aşağıdaki komut çalıştırılır:

```bash
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  check perf
```

*Disk fsync gecikmesinin (Fsync Latency) **10ms altında** olması gerekir. Bunun için etcd sunucularında mutlaka yüksek hızlı **NVMe SSD** diskler kullanılmalıdır.*

### etcd Veritabanı Temizliği (Compaction ve Defrag)

etcd veritabanı zamanla şişer (Maksimum limit varsayılan olarak 8GB'tır). Boş alanları geri kazanmak için compaction ve defragmentation işlemleri yapılır:

```bash
# 1. Eski revizyonları temizle (Compaction)
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 compact <revizyon-numarasi>

# 2. Disk alanını geri kazan (Defrag)
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 defrag
```

---

## 3. İşletim Sistemi Kernel Ayarları

Kubernetes düğümlerinizin yüksek trafik altında tıkanmaması için Linux çekirdeği düzeyinde `/etc/sysctl.d/99-kubernetes.conf` dosyası oluşturularak şu performans ayarları yapılmalıdır:

```ini
# TCP bağlantı kuyruk limiti (tıkanmaları önler)
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8192

# Dosya açma limitleri
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192

# Kubernetes sanal bellek (swap) istemez
vm.swappiness = 0
vm.overcommit_memory = 1
```

*Ayarları uygulamak için `sysctl -p /etc/sysctl.d/99-kubernetes.conf` komutunu çalıştırın.*

---

## 4. Kubernetes Üzerinde Yük Testi (k6)

Canlıya çıkmadan önce sistemin performans sınırlarını görmek için küme içinde **k6** yük testi aracı kullanılabilir. Test senaryosu bir JavaScript dosyası olarak bir ConfigMap'e yüklenir ve pod olarak çalıştırılır:

```javascript
// k6-script.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 50 },  // 50 kullanıcıya yüksel (Ramp-up)
    { duration: '3m', target: 100 }, // 3 dakika boyunca 100 kullanıcıda kal
    { duration: '1m', target: 0 },   // Yavaşça durdur
  ],
  thresholds: {
    http_req_duration: ['p(99)<500'], // İsteklerin %99'u 500ms altında olmalı
    http_req_failed: ['rate<0.01'],   // Hata oranı %1'den az olmalı
  },
};

export default function () {
  const res = http.get('http://backend-service.production.svc.cluster.local/api/healthz');
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.1);
}
```

---

## 5. FinOps ve Kubecost ile Maliyet Yönetimi

Bulut ortamlarında çalışan Kubernetes kümelerinin bütçeyi tüketmesini engellemek için **Kubecost** ile maliyet görünürlüğü sağlanmalıdır.

### Kubecost Kurulumu (Helm)

```bash
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/
helm install kubecost cost-analyzer/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set global.prometheus.enabled=false \
  --set global.prometheus.fqdn=http://prometheus-k8s.monitoring:9090
```

### Temel Kavram: Request vs. Usage (İsraf Analizi)

Maliyet yönetimindeki en temel israf, podların talep ettiği kaynak (**Request**) ile gerçekte kullandığı kaynak (**Usage**) arasındaki uçurumdur.

* **Örnek:** Geliştirici poduna 4 CPU rezerve etmiş (Request Cost faturalandırılır) ancak uygulama gerçekte 0.1 CPU kullanmaktadır (Usage). Kubecost arayüzünde bu durum **Low Efficiency (Düşük Verimlilik)** olarak işaretlenir ve size otomatik **Right-sizing (Doğru Boyutlandırma)** önerileri sunulur.

### Prometheus Maliyet Metrikleri (PromQL)

Maliyetleri Grafana üzerinde görselleştirmek için şu PromQL sorgusu kullanılabilir (Örnek: AWS us-east-1 için CPU saatlik $0.048 fiyattan):

```promql
# Namespace bazında aylık tahmini rezerve CPU maliyeti
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace) * 0.048 * 24 * 30
```

---

## 6. Özet

Kapasite planlaması ve performans optimizasyonu sürekli devam eden bir süreçtir. **FinOps kültürü** gereği; düzenli olarak VPA/Goldilocks önerilerini incelemek, kullanılmayan PVC disklerini silmek ve atıl namespace'leri temizlemek, kümenizin hem hızlı çalışmasını hem de bütçe dostu kalmasını sağlayacaktır.

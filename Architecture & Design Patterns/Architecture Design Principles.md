# Kubernetes Mimari Tasarım Prensipleri

Bir Kubernetes cluster'ı tasarlarken verilen kararlar yıllarca etkisini sürdürür. Bu bölüm, mimari düzeydeki kritik kararları ve trade-off'ları ele alır.

---

## Cluster Topolojisi Tasarımı

### Tek Cluster vs Çoklu Cluster

```
Tek Cluster:
  ✅ Operasyonel basitlik
  ✅ Düşük maliyet
  ❌ Blast radius büyük (bir hata her şeyi etkiler)
  ❌ Multi-tenant izolasyon zor
  Kimler için: Küçük ekip, tek ürün

Çoklu Cluster:
  ✅ Güçlü izolasyon (prod/staging/dev ayrı)
  ✅ Blast radius küçük
  ✅ Farklı K8s versiyonu çalıştırılabilir
  ❌ Operasyonel yük artar
  ❌ Maliyet yüksek
  Kimler için: Büyük ekip, compliance gereksinimleri, enterprise
```

### Namespace Stratejisi

```yaml
# Model 1: Ekip bazlı namespace
# Her ekip kendi namespace'inde çalışır
namespaces:
  - team-payments
  - team-orders
  - team-platform

# Model 2: Environment bazlı namespace
# Tek cluster, farklı env'ler namespace ile ayrılır
namespaces:
  - development
  - staging
  - production

# Model 3: Uygulama bazlı namespace (önerilen)
# Her uygulama/servis grubu kendi namespace'inde
namespaces:
  - orders-prod
  - orders-staging
  - payments-prod
  - monitoring
  - ingress-nginx
```

---

## Network Mimarisi

### CNI Seçimi

| CNI | Güçlü Yön | Zayıf Yön | Tercih |
|:----|:----------|:----------|:-------|
| **Cilium** | eBPF performansı, NetworkPolicy, Hubble | Karmaşık kurulum | 2026 standartı |
| **Flannel** | Basit, stabil | Zayıf NetworkPolicy | Küçük cluster |
| **Calico** | Güçlü NetworkPolicy, BGP | eBPF desteği sınırlı | Enterprise |
| **Weave** | Encrypt by default | Yavaş | Güvenlik odaklı |

### Traffic Flow Mimarisi

```
İnternet
    │
[Cloud LB / MetalLB]
    │
[Ingress Controller — NGINX/Traefik/Istio Gateway]
    │
[Service — ClusterIP]
    │
[Pod]
    │
[Downstream Services — via Service DNS]
```

### East-West vs North-South

```
North-South (Dış trafik):
  İnternet → Ingress → Pod
  Güvenlik: WAF, DDoS koruması, TLS

East-West (Servisler arası):
  Pod A → Pod B (cluster içi)
  Güvenlik: NetworkPolicy, mTLS (Istio)
```

---

## Stateful vs Stateless Mimari Kararı

### Stateless (Tercih Edilmeli)

```yaml
# Stateless: Her request bağımsız, herhangi pod karşılayabilir
# Session verisi → Redis (dışarıda)
# Dosya → S3 (dışarıda)

spec:
  replicas: 10    # Dilediğiniz kadar replika
  strategy:
    type: RollingUpdate
```

### Stateful (Gerektiğinde)

```yaml
# Stateful: Pod kimliği önemli, veri pod'a bağlı
# Kullanım: DB, cache cluster, message queue

kind: StatefulSet
spec:
  serviceName: "mysql-headless"
  replicas: 3
  volumeClaimTemplates:       # Her pod kendi PVC'si
  - metadata:
      name: data
    spec:
      storageClassName: longhorn
      resources:
        requests:
          storage: 100Gi
```

---

## Güvenlik Mimarisi (Defense in Depth)

```
Katman 1: Network       → NetworkPolicy (kimler konuşabilir)
Katman 2: Service Mesh  → mTLS (şifreli iletişim)
Katman 3: Pod           → SecurityContext (root olmayan user)
Katman 4: RBAC          → En az yetki prensibi
Katman 5: Secret        → External Secrets (vault/cloud)
Katman 6: Image         → Trivy scan, signed images
Katman 7: Policy        → Kyverno (admission kontrolü)
Katman 8: Runtime       → Falco (anomali tespiti)
```

---

## Kapasite Planlama

### Node Boyutlandırma

```
# Küçük node'lar mı? Büyük node'lar mı?

Küçük (4 CPU, 8GB) × 20:
  ✅ Tek node arızası az etki
  ✅ Pod packing daha esnek
  ❌ Daha fazla node yönetimi
  ❌ DaemonSet overhead (her node için 1 pod)

Büyük (64 CPU, 256GB) × 3:
  ✅ DaemonSet overhead düşük
  ✅ Yönetim kolay
  ❌ Node arızası büyük etki
  ❌ Pod packing verimsiz (büyük pod sığmayabilir)

Öneri: Orta boy node'lar (16-32 CPU, 64-128GB) × N
```

### etcd Boyutlandırma

```bash
# etcd kritik metrikler:
# - Cluster boyutu: 1 (dev), 3 (prod), 5 (HA prod)
# - Disk: SSD zorunlu, nvme ideal
# - Bellek: Minimum 8GB, önerilen 16GB
# - Ağ: Düşük latency — etcd node'ları birbirine yakın olmalı

# etcd veritabanı boyutu kontrolü
etcdctl endpoint status --write-out=table
# DB SIZE: < 2GB ideal, 8GB'a kadar tolere edilir, max 8GB
```

---

## Disaster Recovery Mimarisi

```
RTO (Recovery Time Objective):    Ne kadar sürede ayağa kalkmalı?
RPO (Recovery Point Objective):   Ne kadar veri kaybı tolere edilir?

Strateji:
  RPO = 0, RTO = 0:  Active-Active multi-cluster (çok pahalı)
  RPO < 1h, RTO < 1h: Velero + hourly backup + standby cluster
  RPO < 24h, RTO < 4h: Velero + daily backup + restore prosedürü
```

```yaml
# Velero ile scheduled backup
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"   # Her gece 02:00
  template:
    includedNamespaces:
    - production
    - staging
    storageLocation: s3-backup
    ttl: 720h              # 30 gün sakla
```

---

## Mimari Karar Defteri (Architecture Decision Records)

Her mimari karar belgelenmeli:

```markdown
# ADR-001: CNI Seçimi

## Durum: Kabul Edildi (2026-01-15)

## Bağlam
Production cluster için CNI seçilmesi gerekiyor.

## Karar
Cilium seçildi.

## Gerekçe
- eBPF ile kube-proxy'den %30 daha iyi performans
- NetworkPolicy desteği Calico ile eşdeğer
- Hubble ile yerleşik network observability
- Aktif CNCF projesi, güçlü community

## Trade-off'lar
- Kurulum karmaşıklığı Flannel'den yüksek
- Ekip Cilium öğrenmek için zaman harcamalı

## Alternatifler
- Flannel: Reddedildi (zayıf NetworkPolicy)
- Calico: Yakın rakip, eBPF desteği daha sınırlı
```

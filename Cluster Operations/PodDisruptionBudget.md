# PodDisruptionBudget (PDB)

PodDisruptionBudget, cluster operasyonları (node drain, upgrade, autoscaler) sırasında bir uygulamanın minimum çalışan pod sayısını garanti eder. Olmadan node drain işlemi tüm pod'ları aynı anda silebilir — servis kesintisi kaçınılmaz olur.

---

## Neden Gerekli?

```
Senaryo: 3 replica'lı deployment, node drain yapılıyor

PDB YOK:
  kubectl drain node-1
  → node-1 üzerindeki TÜM pod'lar silindi
  → Eğer 3'ü de aynı node'daydı → %100 kesinti

PDB VAR (minAvailable: 2):
  kubectl drain node-1
  → Sadece 1 pod silindi (2 pod çalışmaya devam ediyor)
  → Yeni pod başka node'da açıldı, sonra bir sonraki silindi
  → Sıfır kesinti
```

**PDB tetikleyen operasyonlar:**
- `kubectl drain` (node bakımı)
- Cluster upgrade (node'lar sırayla drain edilir)
- Cluster Autoscaler (node scale-down)
- `kubectl delete node`

---

## Temel Yapı

```yaml
# minAvailable — her zaman en az N pod çalışmalı
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: production
spec:
  minAvailable: 2          # En az 2 pod çalışmalı
  selector:
    matchLabels:
      app: api
```

```yaml
# maxUnavailable — aynı anda en fazla N pod kapalı olabilir
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: production
spec:
  maxUnavailable: 1        # Aynı anda en fazla 1 pod kapalı
  selector:
    matchLabels:
      app: api
```

```yaml
# Yüzde ile (10 replica → %20 = 2 pod unavailable)
spec:
  maxUnavailable: "20%"
  selector:
    matchLabels:
      app: api
```

---

## Gerçek Dünya Örnekleri

### Web Uygulaması (5 replica)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: production
spec:
  minAvailable: 3          # 5 replica'dan en az 3'ü çalışmalı
  selector:
    matchLabels:
      app: web
      tier: frontend
```

### Kafka Consumer (10 replica)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: kafka-consumer-pdb
  namespace: production
spec:
  maxUnavailable: "30%"    # Aynı anda max 3 consumer kapalı
  selector:
    matchLabels:
      app: order-consumer
```

### Kritik Servis (Tek node dahi olsa çalışmalı)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payment-pdb
  namespace: production
spec:
  minAvailable: 1          # Minimum 1 pod her zaman ayakta
  selector:
    matchLabels:
      app: payment-service
```

### StatefulSet — Veritabanı

```yaml
# Postgres cluster — 3 node, leader seçimi kritik
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: postgres-pdb
  namespace: production
spec:
  minAvailable: 2          # Quorum için en az 2 node
  selector:
    matchLabels:
      app: postgres
      role: replica         # Sadece replica'lara uygula
```

---

## PDB ve Node Drain Etkileşimi

```bash
# PDB olan bir deployment'ı drain et
kubectl drain node-1 \
  --ignore-daemonsets \
  --delete-emptydir-data

# PDB ihlali olursa drain bekler:
# evicting pod production/api-xxx
# error when evicting pods/"api-xxx" ...
# pod disruption budget "api-pdb" is violated
# → Drain otomatik bekler, başka pod hazır olunca devam eder

# Zorla geçmek (PDB'yi atla — TEHLIKELI!)
kubectl drain node-1 --disable-eviction   # Son çare, sadece emergency'de
```

```bash
# PDB durumunu kontrol et
kubectl get pdb -n production
# NAME       MIN AVAILABLE  MAX UNAVAILABLE  ALLOWED DISRUPTIONS  AGE
# api-pdb    2              N/A              1                    5d
# web-pdb    3              N/A              2                    5d

# Detaylı bilgi
kubectl describe pdb api-pdb -n production
```

---

## PDB Olmayan Namespace Tespiti

```bash
# PDB olmayan deployment'lar (1+ replica)
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  deploys=$(kubectl get deploy -n $ns \
    --field-selector='status.replicas>0' \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  for d in $deploys; do
    labels=$(kubectl get deploy $d -n $ns \
      -o jsonpath='{.spec.selector.matchLabels}')
    # PDB selector eşleşmesini basit kontrol
    pdb_count=$(kubectl get pdb -n $ns 2>/dev/null | wc -l)
    if [ "$pdb_count" -le 1 ]; then
      echo "⚠️  PDB YOK: $ns/$d"
    fi
  done
done
```

---

## PDB Anti-Pattern'lar

```yaml
# ❌ YANLIŞ — minAvailable = replica sayısı
# Hiçbir pod silinemez → drain sonsuza kadar bekler!
spec:
  minAvailable: 3   # 3 replica'lı deployment için — drain ASLA tamamlanamaz
```

```yaml
# ✅ DOĞRU — bir eksiği tolere et
spec:
  minAvailable: 2   # 3 replica için — 1 pod drain edilebilir
```

```yaml
# ❌ YANLIŞ — maxUnavailable: 0 ve minAvailable: replica sayısı birlikte
# Kilitlenme! Hiç pod taşınamaz
spec:
  maxUnavailable: 0   # Bu da drain'i dondurur
```

---

## Kyverno ile PDB Zorunlu Kılma

```yaml
# Production'da PDB olmayan deployment'ı reddet
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-pdb
spec:
  validationFailureAction: Warn    # Önce Warn, sonra Enforce yap
  rules:
  - name: check-pdb-exists
    match:
      any:
      - resources:
          kinds: [Deployment]
          namespaces: [production]
    validate:
      message: "Production deployment'ları için PodDisruptionBudget zorunludur"
      deny:
        conditions:
          any:
          - key: "{{ request.object.spec.replicas }}"
            operator: GreaterThan
            value: 1
```

> [!IMPORTANT]
> Her production Deployment ve StatefulSet için PDB oluşturun. Kural basit: `replica sayısı - 1 = minAvailable`. Tek replica'lı servisler için `minAvailable: 0` (PDB var ama drain'e izin ver) veya replica sayısını artırın.

> [!WARNING]
> `minAvailable` değerini replica sayısına eşitlemeyin. Bu, node drain'i sonsuza kadar bloklar ve cluster upgrade'i dondurur.

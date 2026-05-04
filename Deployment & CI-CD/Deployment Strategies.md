# Deployment Strategies

Kubernetes'te uygulama güncellemelerini nasıl yayınladığın, kesinti süresi ve risk profilini doğrudan belirler. Her strateji farklı bir denge kurar.

---

## Stratejilere Genel Bakış

```
RollingUpdate   → Varsayılan. Yavaş yavaş güncelle. Düşük risk, düşük kesinti.
Recreate        → Önce sil, sonra başlat. Kesinti var ama basit.
Blue/Green      → İki ortam, anlık geçiş. Hızlı rollback, yüksek kaynak.
Canary          → %5 → %20 → %100. En güvenli, en yavaş.
A/B Testing     → Header/cookie bazlı yönlendirme. Özellik karşılaştırma.
```

---

## RollingUpdate (Varsayılan)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
spec:
  replicas: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2         # Aynı anda 2 ekstra pod başlat
      maxUnavailable: 0   # Hiç pod kapatma (sıfır kesinti)
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: company/api:v2.0    # Yeni versiyon
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

```bash
# Güncelleme yayılımını izle
kubectl rollout status deployment/api -n production
kubectl rollout history deployment/api -n production

# Geri al
kubectl rollout undo deployment/api -n production
kubectl rollout undo deployment/api --to-revision=3 -n production
```

---

## Recreate

```yaml
spec:
  strategy:
    type: Recreate    # Tüm pod'ları sil → yenilerini başlat
```

```
Ne zaman kullan:
  ✅ Database migration gerektiren güncelleme (iki versiyon aynı anda çalışmamalı)
  ✅ Shared persistent volume kullanan uygulamalar
  ❌ Production web servisleri (kesinti var)
```

---

## Blue/Green Deployment

```yaml
# Blue (eski) — çalışıyor
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-blue
  namespace: production
spec:
  replicas: 5
  selector:
    matchLabels:
      app: api
      version: blue
  template:
    metadata:
      labels:
        app: api
        version: blue
    spec:
      containers:
      - name: api
        image: company/api:v1.0
---
# Green (yeni) — hazırlan
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-green
  namespace: production
spec:
  replicas: 5
  selector:
    matchLabels:
      app: api
      version: green
  template:
    metadata:
      labels:
        app: api
        version: green
    spec:
      containers:
      - name: api
        image: company/api:v2.0
---
# Service — hangi versiyona gönder?
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  selector:
    app: api
    version: blue    # Burası değişince geçiş olur!
```

```bash
# Green tamamen hazır olunca → Service'i green'e çevir
kubectl patch service api-service -n production \
  -p '{"spec":{"selector":{"version":"green"}}}'

# Sorun varsa anında geri al
kubectl patch service api-service -n production \
  -p '{"spec":{"selector":{"version":"blue"}}}'

# Sorun yok → blue'yu sil
kubectl delete deployment api-blue -n production
```

---

## Canary Deployment

```yaml
# Stable: 9 replica
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: api
      track: stable
  template:
    metadata:
      labels:
        app: api
        track: stable
    spec:
      containers:
      - name: api
        image: company/api:v1.0
---
# Canary: 1 replica = %10 trafik
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
      track: canary
  template:
    metadata:
      labels:
        app: api
        track: canary
    spec:
      containers:
      - name: api
        image: company/api:v2.0
---
# Service her ikisini görür (track olmadan)
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  selector:
    app: api    # track yok → %90 stable + %10 canary
```

```bash
# Canary sağlıklıysa → kademeli artır
kubectl scale deployment api-canary --replicas=3   # %25
kubectl scale deployment api-stable --replicas=7

kubectl scale deployment api-canary --replicas=5   # %50
kubectl scale deployment api-stable --replicas=5

# Tam geçiş
kubectl scale deployment api-canary --replicas=10
kubectl delete deployment api-stable
```

---

## Argo Rollouts ile Otomatik Canary

```yaml
# Manuel canary yerine otomatik metrik bazlı ilerleme
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api-rollout
spec:
  replicas: 10
  strategy:
    canary:
      steps:
      - setWeight: 10       # %10 → bekle
      - pause: {duration: 5m}
      - setWeight: 30       # %30 → bekle
      - pause: {duration: 10m}
      - analysis:           # Metrik analizi
          templates:
          - templateName: success-rate
      - setWeight: 60
      - pause: {duration: 10m}
      - setWeight: 100
      canaryMetadata:
        labels:
          track: canary
      stableMetadata:
        labels:
          track: stable
```

---

## Strateji Seçim Rehberi

| Durum | Strateji |
|:------|:---------|
| Standart web servisi güncellemesi | RollingUpdate |
| DB migration gereken güncelleme | Recreate |
| Sıfır kesinti + anlık rollback gerekli | Blue/Green |
| Riskli değişiklik, yavaş yay | Canary |
| Özellik karşılaştırma, A/B test | Argo Rollouts + Header routing |
| Tam otomatik, metrik bazlı | Argo Rollouts |

> [!TIP]
> `maxUnavailable: 0` ve `maxSurge: 1` kombinasyonu en güvenli RollingUpdate konfigürasyonudur. Update sürer ama hiç pod kullanım dışı kalmaz — readinessProbe'un doğru tanımlı olmasına dikkat et.

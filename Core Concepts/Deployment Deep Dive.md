# Deployment Deep Dive

Deployment, Kubernetes'in en temel ve en çok kullanılan iş yükü objesidir. Pod'ları doğrudan değil, bir ReplicaSet üzerinden yönetir. Bu mimari, sıfır kesintili güncelleme ve anlık rollback'i mümkün kılar.

---

## Deployment → ReplicaSet → Pod İlişkisi

```
Deployment (desired state tanımı)
    │
    ├── ReplicaSet v1 (eski — 0 replica)
    └── ReplicaSet v2 (yeni — 3 replica) ← Aktif
              ├── Pod-1
              ├── Pod-2
              └── Pod-3
```

Her güncelleme yeni bir ReplicaSet oluşturur. Eski ReplicaSet silinmez — rollback için saklanır (`revisionHistoryLimit`).

---

## Tam Deployment Anatomisi

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
  labels:
    app: api
    version: v2.1.0
spec:
  # Kaç pod çalışsın?
  replicas: 3

  # Kaç eski ReplicaSet saklanır?
  revisionHistoryLimit: 5        # Varsayılan: 10

  # Pod seçici — ReplicaSet hangi pod'lardan sorumlu?
  selector:
    matchLabels:
      app: api

  # Güncelleme stratejisi
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1          # Güncelleme sırasında en fazla 1 pod kapalı
      maxSurge: 1                # Geçici olarak 1 fazla pod açılabilir

  # Bir pod'un en az kaç saniye "Ready" kalması gerekir?
  minReadySeconds: 10

  # Güncelleme bu sürede bitmezse başarısız say
  progressDeadlineSeconds: 600   # 10 dakika

  template:
    metadata:
      labels:
        app: api                  # selector ile eşleşmeli
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
      - name: api
        image: ghcr.io/company/api:v2.1.0
        ports:
        - containerPort: 8080

        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"

        readinessProbe:
          httpGet:
            path: /readyz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          successThreshold: 1
          failureThreshold: 3

        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3

        # Graceful shutdown
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 5"]

      # Container kapanmadan önce bekleme süresi
      terminationGracePeriodSeconds: 30

      # Pod dağılımı — aynı node'da çok pod olmasın
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: api
```

---

## Güncelleme Mekanizması (RollingUpdate)

```
Başlangıç: [v1][v1][v1]  (3 pod, maxUnavailable=1, maxSurge=1)

Adım 1: Yeni ReplicaSet başla
[v1][v1][v1][v2]   (surge: 1 fazla pod — toplam 4)

Adım 2: v1'den 1 pod kapat
[v1][v1][v2]       (maxUnavailable=1 sınırına uygun)

Adım 3: Yeni v2 pod ready olunca
[v1][v1][v2][v2]   → [v1][v2][v2] → [v2][v2][v2]

Son: Eski ReplicaSet 0 replica'ya iner (silinmez)
```

### minReadySeconds Kritik Rolü

```yaml
minReadySeconds: 30
# Pod "Running" değil, 30 saniye boyunca "Ready" kaldıktan sonra
# "Available" sayılır. Bu süre dolmadan bir sonraki pod güncellenmez.
# Erken "healthy" görünüp crash olan pod'ları yakalamak için kritik.
```

---

## Rollout Yönetimi

```bash
# Güncelleme başlat
kubectl set image deployment/api api=ghcr.io/company/api:v2.2.0 -n production

# veya patch ile
kubectl patch deployment api -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"api","image":"ghcr.io/company/api:v2.2.0"}]}}}}'

# Rollout durumunu izle
kubectl rollout status deployment/api -n production
# Waiting for deployment "api" rollout to finish: 1 out of 3 new replicas have been updated...

# Geçmişi gör
kubectl rollout history deployment/api -n production
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         v2.1.0 → v2.2.0
# 3         hotfix: fix memory leak

# Belirli revision detayı
kubectl rollout history deployment/api -n production --revision=2

# Bir önceki versiyona rollback
kubectl rollout undo deployment/api -n production

# Belirli revision'a rollback
kubectl rollout undo deployment/api -n production --to-revision=1

# Güncellemeyi duraklat (canary manuel kontrol)
kubectl rollout pause deployment/api -n production

# Devam ettir
kubectl rollout resume deployment/api -n production

# Restart (image değişmedi ama pod'ları yenile)
kubectl rollout restart deployment/api -n production
```

---

## Değişiklik Nedeni Kayıt

```bash
# kubectl annotate ile change-cause ekle (rollout history'de görünür)
kubectl annotate deployment/api \
  kubernetes.io/change-cause="v2.2.0: Add payment retry logic" \
  -n production

# Ya da doğrudan --record flag (deprecated, annotation önerilen)
kubectl set image deployment/api api=v2.2.0 -n production
kubectl annotate deployment/api kubernetes.io/change-cause="v2.2.0 release" -n production
```

---

## Recreate Stratejisi

```yaml
# Tüm eski pod'ları öldür, sonra yenilerini başlat
# Kesinti yaşanır! Stateful uygulamalar veya tek port bağlayıcılar için
strategy:
  type: Recreate
# Akış: [v1][v1][v1] → [] → [v2][v2][v2]
```

---

## Deployment Sorun Giderme

```bash
# Deployment neden ilerlemedi?
kubectl describe deployment api -n production
# "Progressing" condition'ına bak:
# Reason: ProgressDeadlineExceeded → progressDeadlineSeconds aşıldı

# ReplicaSet durumu
kubectl get rs -l app=api -n production
# NAME          DESIRED   CURRENT   READY   AGE
# api-v2abc     3         3         2       5m   ← 2/3 ready, biri sorunlu
# api-v1xyz     0         0         0       1h   ← eski, rollback için saklı

# Hangi pod'lar sorunu yaşıyor?
kubectl get pods -l app=api -n production
kubectl describe pod <sorunlu-pod> -n production

# Rollout takılmış → zorla rollback
kubectl rollout undo deployment/api -n production
```

---

## Prometheus ile Deployment Monitörleme

```promql
# Deployment'ın kaç replica'sı istendi vs hazır?
kube_deployment_spec_replicas{deployment="api"} -
kube_deployment_status_replicas_available{deployment="api"} > 0

# Rollout süresi (son güncelleme ne kadar sürdü?)
kube_deployment_status_condition{condition="Progressing", status="True"}

# Deployment başarısız mı?
kube_deployment_status_condition{condition="Available", status="False"}
```

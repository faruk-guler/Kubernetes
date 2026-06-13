# Pod ve Kubernetes Nesneleri

Kubernetes'te her şey bir **nesne (object)** olarak tanımlanır. Bu nesneler YAML veya JSON formatında bildirilir ve API Server tarafından yönetilir. En temel nesne **Pod**'dur; geri kalan her şey pod'ları farklı şekillerde yönetmek için var olur.


---

## Pod

Pod, Kubernetes'in en küçük dağıtım birimidir. Bir pod içinde **bir veya daha fazla container** çalışabilir; bu container'lar aynı ağ ve depolama alanını paylaşır.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-pod
  namespace: production
  labels:
    app: web
    tier: backend
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
spec:
  restartPolicy: Always               # Always | OnFailure | Never
  terminationGracePeriodSeconds: 30   # Kapanırken uygulamaya tanınan süre

  securityContext:                    # Pod düzeyinde güvenlik
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000

  containers:
  - name: app
    image: ghcr.io/company/app:v2.1
    imagePullPolicy: IfNotPresent     # Always | IfNotPresent | Never
    ports:
    - containerPort: 8080
      name: http

    resources:
      requests:
        cpu: "200m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"

    securityContext:
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]

    readinessProbe:
      httpGet:
        path: /readyz
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10

    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 15
```

> [!IMPORTANT]
> Pod'lar doğrudan oluşturulmaz — her zaman bir **Deployment**, **StatefulSet** veya **DaemonSet** üzerinden yönetilir. Aksi hâlde pod çöktüğünde yeniden başlatılmaz.

---

## Deployment

Deployment, stateless (durumsuz) uygulamalar için en yaygın kullanılan nesnedir. Pod'ları ReplicaSet üzerinden yönetir, rolling update ve rollback sağlar.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: production
spec:
  replicas: 3
  revisionHistoryLimit: 5            # Kaç eski ReplicaSet saklanır?
  selector:
    matchLabels:
      app: web-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                    # Geçici olarak 1 fazla pod açılabilir
      maxUnavailable: 0              # Güncelleme sırasında kapalı pod sayısı
  minReadySeconds: 10                # Pod en az 10 saniye "Ready" kalmalı
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: ghcr.io/company/web:v1.2.0
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
```

### Rollout Komutları

```bash
# Güncelleme durumunu izle
kubectl rollout status deployment/web-app -n production

# Revizyon geçmişini görüntüle
kubectl rollout history deployment/web-app -n production

# Bir önceki versiyona geri al
kubectl rollout undo deployment/web-app -n production

# Belirli bir revizyona dön
kubectl rollout undo deployment/web-app --to-revision=2 -n production

# Güncellemeyi duraklat / devam ettir
kubectl rollout pause deployment/web-app -n production
kubectl rollout resume deployment/web-app -n production

# Pod'ları yeniden başlat (image değişmeden)
kubectl rollout restart deployment/web-app -n production
```

---

## StatefulSet

StatefulSet, veritabanları gibi **durumlu (stateful)** uygulamalar içindir. Her pod sabit bir isim ve kalıcı depolama alır.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: production
spec:
  serviceName: "postgres-headless"    # ClusterIP: None olan servis
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"

  volumeClaimTemplates:               # Her pod için ayrı PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: longhorn
      resources:
        requests:
          storage: 50Gi
```

**StatefulSet Özellikleri:**
- Pod isimleri sabit: `postgres-0`, `postgres-1`, `postgres-2`
- Sıralı başlatma: `postgres-0` hazır olmadan `postgres-1` başlamaz
- Sıralı silme: Ters sırayla (`postgres-2` → `postgres-1` → `postgres-0`)

---

## DaemonSet

DaemonSet, **her node'da tam olarak bir pod** çalıştırır. Yeni node eklendiğinde pod otomatik başlar.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-log-collector
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:2.2
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

**Kullanım alanları:** Log toplayıcılar (Fluentbit), metrik agent'lar (node-exporter), CNI plugin'ler, güvenlik agent'ları (Falco).

---

## Job & CronJob

```yaml
# Tek seferlik görev
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 3
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: migrate
        image: ghcr.io/company/migrator:v1
        command: ["python", "manage.py", "migrate"]
---
# Zamanlanmış görev
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"       # Her gece 02:00
  concurrencyPolicy: Forbid   # Önceki bitmeden yenisi başlamasın
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: ghcr.io/company/backup:v1
```

---

## Label ve Annotation

```bash
# Label ile listeleme
kubectl get pods -l app=web-app
kubectl get pods -l env=prod,tier=frontend
kubectl get pods -l 'env in (prod,staging)'

# Label ekle / kaldır
kubectl label pod my-pod env=prod
kubectl label pod my-pod env-          # Kaldır (- ile)

# Annotation ekle
kubectl annotate deployment web-app \
  kubernetes.io/change-cause="v2.1.0: Fix memory leak"
```

| Özellik | Label (Etiket) | Annotation (Açıklama) |
|:--------|:---------------|:----------------------|
| **Amacı** | Gruplama, Seçim (Selector) | Ek bilgi, Metadata, Tooling |
| **Sorgulanabilir?** | Evet (`-l`) | Hayır |
| **Boyut sınırı** | Kısa (63 karakter) | Büyük veri tutabilir |
| **Örnek** | `app: nginx`, `env: prod` | `change-cause: v2`, `build: abc123` |

---

## Resource Quota & LimitRange

```yaml
# Namespace'e kaynak sınırı
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "100"
    services.loadbalancers: "2"
    persistentvolumeclaims: "20"
---
# Belirtilmemiş pod'lara varsayılan limit
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-alpha
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "4"
      memory: "8Gi"
```

---

## Özel Registry Erişimi

```bash
# Private registry için secret oluştur
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=$USERNAME \
  --docker-password=$TOKEN \
  -n production
```

```yaml
spec:
  imagePullSecrets:
  - name: regcred
  containers:
  - name: app
    image: ghcr.io/company/private-app:v1
```

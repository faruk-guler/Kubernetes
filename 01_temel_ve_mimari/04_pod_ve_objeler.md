# Pod ve Kubernetes Nesneleri

## 4.1 Pod

Pod, Kubernetes'in en küçük dağıtım birimidir. Bir Pod içinde **bir veya daha fazla konteyner** çalışabilir; bu konteynerler aynı ağ ve depolama alanını paylaşır.

```yaml
apiVersion: v1                        # Kaynak Türü
kind: Pod                             # Obje Tipi
metadata:
  name: techops-pod                   # Pod için benzersiz isim
  labels:                             # Organizasyon etiketleri
    app: techops
    tier: backend
  annotations:                        # İzleme araçları için veri
    "prometheus.io/scrape": "true"
spec:
  restartPolicy: Always               # Yeniden başlatma ilkesi (Always, OnFailure, Never)
  terminationGracePeriodSeconds: 30   # Kapanırken uygulamaya tanınan süre
  
  securityContext:                    # Pod düzeyinde güvenlik
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000

  containers:
  - name: nginx-container
    image: nginx:1.27
    imagePullPolicy: IfNotPresent
    ports:
    - containerPort: 80
      name: http
    
    resources:                        # Kaynak limitleri (Üretim standartı)
      requests:
        cpu: "250m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"

    securityContext:                  # Konteyner düzeyinde kısıtlama
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop: ["ALL"]
```

> [!IMPORTANT]
> Pod'lar direkt oluşturulmaz; her zaman bir **Deployment**, **StatefulSet** veya **DaemonSet** üzerinden yönetilir. Aksi hÃ¢lde pod çökünce yeniden başlatılmaz.

### 4.1.1 ReplicaSet (Hiyerarşi)
Deployment nesnesi, pod'ları doğrudan yönetmez. Arada bir **ReplicaSet** katmanı bulunur. Deployment bir güncelleme aldığında yeni bir ReplicaSet oluşturur ve eskisini kademeli olarak (Scale down) kapatır.
- **Görevi:** Belirlenen sayıdaki pod kopyasının her an ayakta olmasını garanti etmektir.
- **Sorgulama:** `kubectl get rs`

## 4.2 Deployment

Deployment, stateless (durumsuz) uygulamalar için en yaygın kullanılan nesnedir. Pod'ları yönetir, rolling update ve rollback sağlar.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  revisionHistoryLimit: 10            # Eski versiyon saklama sınırı
  selector:
    matchLabels:
      app: web-app
  strategy:
    type: RollingUpdate               # Sıfır downtime güncelleme
    rollingUpdate:
      maxSurge: 1                     # Güncellemede fazladan pod sayısı
      maxUnavailable: 0               # Güncellemede kapanabilir pod sayısı
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: my-registry/web-app:v1.2.0
          limits:
            cpu: "1000m"
            memory: "512Mi"

### 4.2.1 Operasyonel Rollout Komutları (Black Belt)
Deployment güncellemelerini yönetmek için kullanılan temel komutlar:

```bash
# Güncelleme durumunu izle
kubectl rollout status deployment/web-app

# Revizyon geçmişini görüntüle
kubectl rollout history deployment/web-app

# Hatalı güncellemeyi geri al (Rollback)
kubectl rollout undo deployment/web-app

# Belirli bir revizyona geri dön
kubectl rollout undo deployment/web-app --to-revision=2

# Güncellemeyi duraklat / devam ettir
kubectl rollout pause deployment/web-app
kubectl rollout resume deployment/web-app
```
```

## 4.3 StatefulSet

StatefulSet, veritabanları gibi **durumlu (stateful)** uygulamalar içindir. Her pod sabit bir isim ve kalıcı depolama alır.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
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
            secretKeyRef: { name: db-secret, key: pass }
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:               # Dinamik disk oluşturma
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 10Gi
```

## 4.4 DaemonSet

DaemonSet, **her node**'da tam olarak bir pod çalıştırır. Log toplayıcılar, ağ ajanları için idealdir.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:3.0
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

## 4.5 Job ve CronJob

```yaml
# Tek seferlik iş
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  completions: 1          # Kaç kez başarılı bitmesi gerekiyor
  parallelism: 1          # Aynı anda kaç pod çalışabilir
  backoffLimit: 4         # Başarısızlık durumunda kaç kez tekrar denesin
  template:
    spec:
      containers:
      - name: migrate
        image: my-app:latest
        command: ["./migrate.sh"]
      restartPolicy: OnFailure
---
# Zamanlanmış tekrarlı iş
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-job
spec:
  schedule: "0 2 * * *"   # Her gece 02:00'de
  concurrencyPolicy: Forbid # Bir önceki bitmeden yenisi başlamasın
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:v1.0
          restartPolicy: OnFailure
```

## 4.6 Label ve Selector

Label'lar kaynakları gruplamak ve bulmak için kullanılır:

```bash
# Label ile pod listele
kubectl get pods -l app=web-app
kubectl get pods -l env=prod,tier=frontend

# Label ekle / kaldır
kubectl label pod my-pod env=prod
kubectl label pod my-pod env-          # label kaldır

## 4.6.1 Label vs Annotation

| Özellik | Label (Etiket) | Annotation (Açıklama) |
|:---|:---|:---|
| **Amacı** | Gruplama, Seçme (Selector) | Ek bilgi, Metadata, Tooling |
| **Sorgulanabilir mi?** | Evet (`kubectl get -l`) | Hayır |
| **Kısıtlamalar** | Karakter kısıtı var (Kısa) | Çok daha büyük veri tutabilir |
| **Örnek Kullanım** | `env: prod`, `app: nginx` | `build: v1.2`, `logs: fluentbit` |

---

## 4.6.2 Gelişmiş İmaj Yönetimi (Image Management)

Konteynerlerin nasıl çekileceği ve özel registry'lere nasıl bağlanılacağı kritiktir.

### ImagePullPolicy Türleri
- **Always:** Her seferinde registry'den tekrar çekilir. (Tag `latest` ise varsayılandır).
- **IfNotPresent:** Localde yoksa çekilir. (En verimli yöntemdir).
- **Never:** Asla çekilmez, sadece local imajlar kullanılır.

### Özel Registry Erişimi (imagePullSecrets)
Özel bir imaj deposundan (Harbor, GitLab, ECR) imaj çekmek için:
```bash
kubectl create secret docker-registry reg-cred \
  --docker-server=<REGISTRY_URL> \
  --docker-username=<USER> \
  --docker-password=<PASS>
```
```yaml
spec:
  imagePullSecrets:
  - name: reg-cred
  containers:
  - name: private-app
    image: <PRIVATE_IMAGE>
```
```

## 4.7 Resource Quota ve LimitRange

```yaml
# Namespace'e kaynak sınırı
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "50"
---
# Varsayılan limit (belirtilmemiş pod'lara)
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-a
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
```


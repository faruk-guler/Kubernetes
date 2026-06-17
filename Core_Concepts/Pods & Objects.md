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

## Label (Etiket) ve Annotation (Açıklama)

Kubernetes nesnelerine ek bilgi (metadata) eklemek için iki temel parametremiz vardır: **Label** ve **Annotation**. Her ikisi de anahtar-değer (key-value) eşleşmesiyle çalışsa da kullanım amaçları ve cluster üzerindeki etkileri tamamen farklıdır.

### 1. Label ve Annotation Arasındaki Temel Felsefe Farkı

* **Label (Etiket):** Kubernetes nesnelerini gruplamak, filtrelemek ve nesneler arasında bağ kurmak için kullanılır. Örneğin, bir `Service` nesnesinin trafiği hangi pod'lara yönlendireceğini seçmesi (`spec.selector`) etiketler sayesinde olur. Bu ilişki kurma özelliğinden ötürü etiketler hassas bilgi sınıfına girer. Yanlışlıkla bir etiketi eklemek veya silmek, uygulamanın trafiğinin kesilmesine veya pod'ların yanlış zamanlanmasına yol açabilir. Bu yüzden her ek bilgiyi label olarak eklemek yanlıştır.
* **Annotation (Açıklama):** Herhangi bir nesneyi gruplama veya seçme (selector) amacıyla kullanmayacağımız, sadece nesneyle ilgili ek/tanımlayıcı bilgi sunmak istediğimiz durumlarda kullanılır. Ayrıca, Kubernetes'in çekirdek bileşeni olmayan fakat cluster'la entegre çalışan harici araçlar (Ingress Controller, çağrı merkezi yazılımları, yedekleme araçları vb.) tarafından okunacak talimatlar veya konfigürasyonlar da buraya yazılır.

> **Örnek Senaryo:** Bir nesneyi kimin oluşturduğu, oluşturulma tarihi veya destek ekibinin e-posta adresi gibi bilgileri label olarak eklemek doğru değildir (çünkü bu bilgileri selector ile sorgulamayacağız). Bu ek bilgileri annotation olarak eklemek en doğru pratik olacaktır. Böylece, örneğin destek ekibinin kullandığı harici bir izleme robotu bu annotation değerini okuyup olası bir arızada ilgili kişiye otomatik mail gönderebilir.

### 2. Adlandırma Kuralları ve Sözdizimi (Syntax)

Bir annotation anahtar (key) alanı şu kurallara uymalıdır:

```
1w2.net/notification-email : admin@example.com
└─Prefix─┘ └──────Key─────┘   └─────Value─────┘
```

* **Prefix (Önek):** Zorunlu değildir. Ancak özellikle harici araçlar kendi konfigürasyonlarını yazarken çakışmayı önlemek için önek kullanırlar (Örn: `nginx.ingress.kubernetes.io/...`).
* **Key (Anahtar):** Maksimum 63 karakter olmalıdır. Alfanümerik bir karakterle başlamalı ve bitmelidir. İçerisinde `.`, `-`, `_` gibi özel karakterler barındırabilir.
* **Value (Değer):** Anahtar kısmındaki kısıtlamalara tabi değildir. Alfanümerik olmayan karakterler ve çok daha uzun metinler barındırabilir.

### 3. YAML Tanımı

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: annotation-pod
  namespace: production
  annotations:
    owner: "mycat"
    notification-email: "admin@example.com"
    releasedate: "01.01.2021"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  containers:
  - name: web-container
    image: nginx:1.27
    ports:
    - containerPort: 80
```

### 4. Yönetim Komutları

```bash
# Label ile listeleme ve filtreleme
kubectl get pods -l app=web-app
kubectl get pods -l env=prod,tier=frontend
kubectl get pods -l 'env in (prod,staging)'

# Dinamik olarak label ekleme ve silme
kubectl label pod my-pod env=prod
kubectl label pod my-pod env-          # Anahtarın sonuna '-' koyarak silinir

# Dinamik olarak annotation ekleme ve silme
kubectl annotate pod annotation-pod owner=mycat
kubectl annotate pod annotation-pod owner-   # Anahtarın sonuna '-' koyarak silinir
```

### 5. Karşılaştırma Özeti

| Özellik | Label (Etiket) | Annotation (Açıklama) |
| :--- | :--- | :--- |
| **Ana Amacı** | Gruplama, Seçim (Selector) | Ek bilgi, Metadata, Harici Araç Yapılandırması |
| **Sorgulanabilir mi?** | Evet (`-l` parametresi ile) | Hayır (Filtreleme amaçlı kullanılamaz) |
| **Boyut Sınırı** | Kısa (Maksimum 63 karakter) | Büyük boyutlu veri veya JSON/YAML tutabilir |
| **Örnek Kullanım** | `app: nginx`, `env: prod` | `owner: mycat`, `nginx.ingress.../ssl-redirect: "true"` |


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

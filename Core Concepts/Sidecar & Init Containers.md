# Sidecar & Init Containers

Kubernetes pod'ları birden fazla container barındırabilir. Bu container'ların rolleri üç gruba ayrılır: **Init Container** (başlangıç hazırlığı), **Sidecar Container** (yardımcı servis), ve **Uygulama Container'ı** (ana iş yükü).

---

## Init Containers

Init container'lar, ana uygulama container'ları **başlamadan önce** tamamlanmak üzere çalışan özel container'lardır. Sıralı çalışırlar — her biri başarıyla tamamlanmadan bir sonraki başlamaz.

### Ne İçin Kullanılır?

- Veritabanının hazır olmasını beklemek (`nslookup db-service`)
- Uygulama config dosyalarını indirmek veya oluşturmak
- Dosya izinlerini veya sahipliğini düzenlemek
- Şema migration'larını çalıştırmak

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp-pod
  labels:
    app: myapp
spec:
  initContainers:
  # 1. Adım: DB hazır olana kadar bekle
  - name: wait-for-db
    image: busybox:1.36
    command: ['sh', '-c', 'until nslookup postgres-service; do echo waiting for DB; sleep 2; done']

  # 2. Adım: Migration çalıştır
  - name: run-migrations
    image: my-app:v2
    command: ['python', 'manage.py', 'migrate']
    env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: url

  containers:
  - name: myapp
    image: my-app:v2
    ports:
    - containerPort: 8080
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
```

### Init Container Özellikleri

| Özellik | Init Container | Uygulama Container |
|---|---|---|
| Çalışma sırası | Sıralı (bir biter, diğeri başlar) | Paralel |
| Başarısızlık davranışı | Pod `restartPolicy`'ye göre yeniden dener | Probe'lara göre restart |
| Probe desteği | ❌ (liveness/readiness yok) | ✅ |
| Kaynak hesabı | En yüksek init isteği geçerlidir | Tüm container'ların toplamı |

---

## Sidecar Containers (Native — Kubernetes v1.29+)

Kubernetes v1.29'dan itibaren **native sidecar desteği** geldi. Sidecar'lar artık `initContainers` altında `restartPolicy: Always` ile tanımlanıyor. Bu sayede init container'ların aksine pod yaşam döngüsü boyunca **çalışmaya devam ediyorlar**.

### Neden Native Sidecar?

Eski yöntemde sidecar'lar normal container olarak tanımlanırdı. Sorun: Job veya CronJob senaryolarında sidecar bitmediği için pod `Completed` durumuna geçemezdi. Native sidecar bu sorunu çözdü.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  initContainers:
  # Native Sidecar: restartPolicy: Always ile tanımlanır
  - name: log-collector
    image: fluentd:v1.16
    restartPolicy: Always          # ← Bu satır sidecar yapar
    volumeMounts:
    - name: app-logs
      mountPath: /var/log/app

  containers:
  - name: main-app
    image: my-app:v2
    volumeMounts:
    - name: app-logs
      mountPath: /app/logs
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"

  volumes:
  - name: app-logs
    emptyDir: {}
```

### Sidecar Kullanım Senaryoları

| Senaryo | Sidecar İmajı |
|---|---|
| Log toplama | `fluentd`, `filebeat`, `promtail` |
| Proxy / mTLS | `envoy`, `istio-proxy` |
| Metrik toplama | `prometheus/node-exporter` |
| Config yenileme | `vault-agent`, `config-reloader` |

---

## Sidecar vs Init Container vs Uygulama Container

| Özellik | Init Container | Sidecar Container | Uygulama Container |
|---|---|---|---|
| Çalışma zamanı | Pod başlamadan önce, kısa süreli | Pod boyunca sürekli | Pod boyunca sürekli |
| Tanım yeri | `initContainers[]` | `initContainers[]` + `restartPolicy: Always` | `containers[]` |
| Probe desteği | ❌ | ✅ | ✅ |
| Diğer container'larla iletişim | Tek yönlü (emptyDir) | ✅ Tam erişim | ✅ Tam erişim |
| Job/CronJob uyumu | ✅ | ✅ (native, v1.29+) | ⚠️ Eski yöntem sorunluydu |

---

## Kaynak Hesabı Kuralı

```
Pod Efektif Kaynağı = max(Init istekleri) + Σ(Container + Sidecar istekleri) + Pod Overhead
```

> [!IMPORTANT]
> Sidecar container'lar kaynak hesabında uygulama container'larıyla **toplanır**; init container'ların en yüksek değeri ise ayrıca hesaba katılır.

---

## Örnek: Istio Sidecar Injection

Istio gibi service mesh'ler pod'lara otomatik sidecar enjekte eder. Manuel olarak da yapılabilir:

```yaml
# Namespace'e label ekleyerek otomatik injection aktif edilir
kubectl label namespace production istio-injection=enabled

# Tek bir pod için devre dışı bırakmak
metadata:
  annotations:
    sidecar.istio.io/inject: "false"
```

---

## Native Sidecar — Başlatma Sırası Garantisi

```
initContainers (sıralı):
  1. wait-for-db  (init)         → tamamlandı ✅
  2. log-collector (native sidecar, restartPolicy:Always) → Ready olana kadar bekle
     ↓ Ready
  3. main-app (container)        → başlayabilir

Eski yöntemde: log-collector normal container'da → başlatma sırası yok!
```

```yaml
spec:
  initContainers:
  # 1. Önce DB bekle (klasik init)
  - name: wait-for-db
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z postgres 5432; do sleep 2; done']

  # 2. Sidecar hazır olana kadar main-app başlamaz (native, K8s 1.29+)
  - name: log-forwarder
    image: fluent/fluent-bit:2.2
    restartPolicy: Always
    readinessProbe:               # ← Sidecar ready olana kadar main-app bekler
      httpGet:
        path: /api/v1/health
        port: 2020
      initialDelaySeconds: 5
    volumeMounts:
    - name: app-logs
      mountPath: /var/log/app

  containers:
  - name: main-app
    image: ghcr.io/company/app:v2
```

---

## Job/CronJob ile Native Sidecar

Eski yöntemde sidecar Job'u tıkıyordu (pod `Completed` olamıyordu). Native sidecar bu sorunu çözdü:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processor
spec:
  template:
    spec:
      initContainers:
      # Native sidecar — Job bitince otomatik kapanır
      - name: vault-agent
        image: hashicorp/vault:1.17.2
        restartPolicy: Always
        args: ["agent", "-config=/etc/vault/config.hcl"]
        volumeMounts:
        - name: secrets
          mountPath: /secrets

      containers:
      - name: processor
        image: ghcr.io/company/processor:v1
        command: ["python", "process.py"]
        volumeMounts:
        - name: secrets
          mountPath: /secrets
      # processor tamamlandı → vault-agent otomatik kapanır → Job Completed ✅

      restartPolicy: OnFailure
      volumes:
      - name: secrets
        emptyDir:
          medium: Memory    # tmpfs — bellekte tut
```

---

## Vault Agent Sidecar Örneği

```yaml
spec:
  initContainers:
  - name: vault-agent
    image: hashicorp/vault:1.15
    restartPolicy: Always       # Native sidecar
    args:
    - agent
    - -config=/etc/vault/config.hcl
    env:
    - name: VAULT_ADDR
      value: "https://vault.company.com"
    volumeMounts:
    - name: vault-config
      mountPath: /etc/vault
    - name: secrets
      mountPath: /secrets       # Secret'ları buraya yazar

  containers:
  - name: app
    image: ghcr.io/company/app:v2
    volumeMounts:
    - name: secrets
      mountPath: /secrets
      readOnly: true

  volumes:
  - name: vault-config
    configMap:
      name: vault-agent-config
  - name: secrets
    emptyDir:
      medium: Memory
```

---

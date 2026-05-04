# ConfigMap ve Secret Yönetimi

Kubernetes'te uygulama yapılandırmaları ve hassas veriler için iki temel nesne: **ConfigMap** (non-sensitive) ve **Secret** (sensitive). Her ikisi de pod'lardan bağımsız olarak yönetilir.

---

## ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  # Key-value çiftleri
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
  DB_HOST: "postgres.production.svc.cluster.local"

  # Çok satırlı dosya içeriği (nginx.conf, properties dosyası vb.)
  nginx.conf: |
    server {
      listen 80;
      location /health { return 200 "ok"; }
      location / {
        proxy_pass http://backend:8080;
      }
    }

  app.properties: |
    server.port=8080
    logging.level.root=INFO
    spring.datasource.url=jdbc:postgresql://postgres:5432/mydb
```

---

## Secret

Secret, hassas verileri `base64` olarak saklar.

> [!IMPORTANT]
> base64 bir **şifreleme değil**, kodlamadır. Secret'lar mutlaka etcd encryption at rest + ESO/Vault ile korunmalıdır.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: production
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=    # base64: "password123"
  username: YWRtaW4=             # base64: "admin"
```

### stringData — base64 olmadan

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
stringData:
  password: "myplainpassword123"    # Kubernetes otomatik base64'e çevirir
  connection-string: "host=postgres port=5432 dbname=mydb user=admin password=myplainpassword123"
```

### Secret Tipleri

| Type | Kullanım |
|:-----|:---------|
| `Opaque` | Genel amaçlı (varsayılan) |
| `kubernetes.io/tls` | TLS sertifika + key çifti |
| `kubernetes.io/dockerconfigjson` | Registry kimlik bilgileri |
| `kubernetes.io/service-account-token` | SA token (otomatik) |
| `kubernetes.io/ssh-auth` | SSH private key |

---

## Kullanım Şekilleri

### Environment Variable (tek key)

```yaml
spec:
  containers:
  - name: app
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
```

### envFrom — Tüm key'leri aktar

```yaml
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef:
        name: app-config
    - secretRef:
        name: db-secret
        optional: true    # Secret yoksa pod başlamayı durdurma
```

### Volume Mount — Dosya olarak

```yaml
spec:
  containers:
  - name: web
    volumeMounts:
    - name: config-vol
      mountPath: /etc/nginx/conf.d
      readOnly: true
    - name: secret-vol
      mountPath: /etc/ssl/certs
      readOnly: true
  volumes:
  - name: config-vol
    configMap:
      name: app-config
      items:                          # Sadece belirli key'leri mount et
      - key: nginx.conf
        path: default.conf
  - name: secret-vol
    secret:
      secretName: tls-secret
      defaultMode: 0400               # Sadece owner okuyabilir
```

### Projection — Birden Fazla Kaynağı Tek Volume'e

```yaml
spec:
  volumes:
  - name: projected-config
    projected:
      sources:
      - configMap:
          name: app-config
      - secret:
          name: db-secret
      - serviceAccountToken:
          audience: api
          expirationSeconds: 3600
          path: token
      - downwardAPI:
          items:
          - path: pod-name
            fieldRef:
              fieldPath: metadata.name
          - path: pod-namespace
            fieldRef:
              fieldPath: metadata.namespace
```

---

## Immutable ConfigMap & Secret

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v2
immutable: true    # Bir kez oluşturulunca değiştirilemez
data:
  VERSION: "2.1.0"
```

**Avantajları:**
- kube-apiserver'ın watch overhead'ini sıfırlar (cluster'da yüzlerce ConfigMap varsa kritik)
- Yanlışlıkla güncelleme riskini ortadan kaldırır
- Yeni versiyon için yeni ConfigMap oluşturup pod'u güncelle

---

## Güncelleme Davranışı (Kritik Bilgi)

| Kullanım | ConfigMap/Secret güncellenince |
|:---------|:-------------------------------|
| **Volume mount** | ~1 dakika içinde pod içindeki dosya otomatik güncellenir |
| **Environment variable** | Pod restart edilene kadar **asla güncellenmez** |

```bash
# Environment variable değişikliği için rolling restart
kubectl rollout restart deployment/my-app -n production

# Değişikliği izle
kubectl rollout status deployment/my-app -n production
```

---

## Reloader — Otomatik Pod Restart

ConfigMap/Secret değiştiğinde pod'ları otomatik restart etmek için:

```bash
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader \
  --namespace kube-system \
  --set reloader.watchGlobally=false    # Sadece annotation'lı resource'ları izle
```

```yaml
# Deployment'a annotation ekle
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
    # veya sadece belirli configmap için:
    configmap.reloader.stakater.com/reload: "app-config"
    secret.reloader.stakater.com/reload: "db-secret"
```

---

## Encryption at Rest

etcd'deki Secret'ları şifrelemek için:

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-random-key>
  - identity: {}    # Eski şifrelenmemiş Secret'lar için fallback
```

```bash
# kube-apiserver'a ekle
--encryption-provider-config=/etc/kubernetes/encryption-config.yaml

# Mevcut Secret'ları yeni şifrelemeyle tekrar yaz
kubectl get secrets -A -o json | kubectl replace -f -
```

---

## Best Practices (2026)

```
✅ ConfigMap: ortam yapılandırmaları, dosya içerikleri
✅ Secret: şifreler, API key, sertifika — Vault/ESO ile yönet
✅ immutable: true — version bazlı config yönetimi
✅ Reloader — otomatik rolling restart
✅ etcd encryption at rest — zorunlu
❌ Secret'ı Git'e koymak — kesinlikle yasak
❌ latest ConfigMap'i env var olarak kullanmak — değişiklik takibi zor
```

> [!TIP]
> ConfigMap/Secret boyutu 1 MB ile sınırlıdır. Büyük yapılandırma dosyaları için S3/GCS gibi harici depolama ve init container kullanın.

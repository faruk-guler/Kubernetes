# ConfigMap ve Secret Yönetimi

Kubernetes'te uygulama yapılandırmaları ve hassas veriler (şifreler, sertifikalar) için iki temel nesne kullanılır.

## 5.1 ConfigMap

ConfigMap, uygulama konfigürasyonlarını (env var, dosya vb.) pod'lardan bağımsız tutmayı sağlar.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  # Basit key-value değerleri
  LOG_LEVEL: "info"
  MAX_CONNECTIONS: "100"
  
  # Çok satırlı dosya içeriği
  nginx.conf: |
    server {
      listen 80;
      location / {
        root /usr/share/nginx/html;
      }
    }
```

## 5.2 Secret

Secret, hassas verileri `base64` formatında saklar (Not: 2026 standartlarında Secret'lar mutlaka KMS veya Vault ile şifrelenmiş olmalıdır).

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  # base64 encoded değerler
  password: cGFzc3dvcmQxMjM=  # 'password123'

---

### 5.2.1 stringData (Black Belt Tip)
Secret oluştururken manuel base64 çevirisiyle uğraşmak yerine `stringData` kullanabilirsiniz. Kubernetes bunu otomatik olarak `data` alanına base64 çevirerek kaydeder.
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret-simple
stringData:
  password: myplainpassword123  # Base64 gerekmez
```

## 5.3 Kullanım Şekilleri

### 1. Ortam Değişkeni (Environment Variable) Olarak

```yaml
spec:
  containers:
  - name: my-app
    env:
    - name: APP_LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    - name: DB_PASS
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password

### 2. Toplu Ortam Değişkeni (envFrom)
Bir ConfigMap veya Secret içindeki **tüm** anahtarları otomatik olarak pod'a aktarmak için kullanılır:

```yaml
spec:
  containers:
  - name: my-app
    envFrom:
    - configMapRef:
        name: app-config
    - secretRef:
        name: db-secret
```

### 3. Dosya (Volume) Olarak Mount Etme

```yaml
spec:
  containers:
  - name: web
    volumeMounts:
    - name: config-volume
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```

## 5.4 Önerilen Uygulamalar (2026 Standartları)

1.  **Immutable Kaynaklar:** Değişmez (immutable) bayrağını kullanarak kube-apiserver üzerindeki yükü azaltın:
    ```yaml
    immutable: true
    ```
2.  **Secret Güvenliği:** Secret'ları asla Git üzerine plain-text koymayın. **SealedSecrets** (Bitnami) veya **External Secrets** kullanın.
3.  **Hayati Bilgi: Güncelleme (Sync) Davranışı** (Denetim Notu):
    - **Volume Mount:** ConfigMap/Secret güncellendiğinde, bu pod'a mount edilen dosya içeriği yaklaşık 1 dakika içinde otomatik olarak güncellenir.
    - **Environment Variable:** ConfigMap/Secret güncellense bile pod içindeki ortam değişkeni **asla güncellenmez**. Yeni değerin yansıması için pod'un mutlaka restart edilmesi (Rolling restart) gerekir.

---
*← [Ana Sayfa](../README.md)*

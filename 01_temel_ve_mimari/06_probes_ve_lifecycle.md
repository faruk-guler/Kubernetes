# Pod Yaşam Döngüsü ve Probe'lar

## 6.0 Pod Yaşam Döngüsü ve Durumları (Phase)

Bir Pod, oluşturulduğu andan yok edilene kadar belirli bir yaşam döngüsü izler. Bu süreci anlamak, "Uygulamam neden çalışmıyor?" sorusunun cevabını bulmak için kritiktir.

### 1. Pod Fazları (Phases)
Pod'un genel durumunun yüksek seviyeli özetidir:

| Faz | Açıklama |
|:---|:---|
| **Pending** | Pod kabul edildi ancak bir veya daha fazla konteyner henüz hazır değil (İmaj çekme veya zamanlanma bekliyor). |
| **Running** | Pod bir node'a bağlandı ve tüm konteynerler oluşturuldu. En az bir konteyner hala çalışıyor veya başlatılıyor. |
| **Succeeded** | Pod'daki tüm konteynerler başarıyla (exit 0) sonlandı ve yeniden başlatılmayacak. |
| **Failed** | En az bir konteyner hata ile (sıfır dışı exit code) sonlandı. |
| **Unknown** | Pod'un durumu bilinemiyor (Genelde Node ile iletişim koptuğunda görülür). |

### 2. Konteyner Durumları (Statuses)
Pod içindeki her bir konteynerin kendi statüsü vardır:
- **Waiting:** Konteyner başlamak için gerekli işlemleri (imaj çekme, secret okuma) yürütüyor.
- **Running:** Konteyner sorunsuz şekilde çalışıyor.
- **Terminated:** Konteyner bir sebeple durdu (Başarılı bitiş veya hata). `kubectl describe` ile hata kodu incelenmelidir.

---

## 6.1 Neden Probe?

Kubernetes, pod'un çalışıp çalışmadığını anlamak için basitçe konteyner process'inin aktif olup olmadığına bakar. Ancak process çalışıyor olsa bile uygulama kilitlenmiş veya hazır olmayabilir. Probe'lar bu sorunu çözer.

| Probe | Amaç | Başarısız Olunca |
|:---|:---|:---|
| **livenessProbe** | Uygulama kilitlendi mi? | Konteyner yeniden başlatılır |
| **readinessProbe** | Trafik almaya hazır mı? | Servis arkasından çıkarılır |
| **startupProbe** | Uygulama başladı mı? | Diğer probe'lar bekler |

## 6.2 Probe Mekanizmaları

### 1. httpGet
Belirlenen path ve port'a HTTP isteği gönderir. 200-399 arası dönerse sağlıklı kabul edilir.
- **host:** Bağlanılacak host ismi (Varsayılan pod IP'sidir).
- **scheme:** Bağlantı protokolü (HTTP veya HTTPS).
- **path:** Erişim sağlanacak URI (Örn: `/healthz`).
- **httpHeaders:** İsteğe eklenecek özel header'lar (Örn: `Custom-Header: Awesome`).

### 2. exec
Konteyner içinde komut çalıştırır. Dönüş kodu `0` ise sağlıklı.

### 3. tcpSocket
Belirlenen porta TCP bağlantısı açmaya çalışır. Başarılıysa sağlıklı.

### 4. grpc (2026 eklentisi)
gRPC Health Checking Protocol'ü kullanır.

## 6.3 Kapsamlı Probe Örneği

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  template:
    spec:
      containers:
      - name: app
        image: my-app:v1.0
        ports:
        - containerPort: 8080

        # Startup Probe — uygulama tam olarak başlayana kadar diğer probe'ları bekletir
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30   # 30 x 10s = 300 saniye max başlangıç süresi
          periodSeconds: 10

        # Liveness Probe — kilitlenmiş uygulamayı yeniden başlatır
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 0    # startupProbe geçtikten sonra başlar
          periodSeconds: 15
          failureThreshold: 3       # 3 başarısızlık = pod restart

        # Readiness Probe — trafik controlü
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1       # 1 başarılı = hazır
          failureThreshold: 3       # 3 başarısız = servisten çıkar
```

### Exec Probe (Veritabanı için)

```yaml
livenessProbe:
  exec:
    command:
    - pg_isready
    - -U
    - postgres
  initialDelaySeconds: 30
  periodSeconds: 10
```

### TCP Probe (Redis için)

```yaml
livenessProbe:
  tcpSocket:
    port: 6379
  initialDelaySeconds: 15
  periodSeconds: 20
```

## 6.4 Probe Parametreleri

| Parametre | Varsayılan | Açıklama |
|:---|:---:|:---|
| `initialDelaySeconds` | 0 | İlk kontrolden önce bekleme |
| `periodSeconds` | 10 | Kontrol aralığı |
| `timeoutSeconds` | 1 | Tek kontrol timeout'u |
| `successThreshold` | 1 | Sağlıklı sayılmak için gereken başarı sayısı |
| `failureThreshold` | 3 | Başarısız sayılmak için gereken hata sayısı |
| `terminationGracePeriodSeconds` | 30 | Probe hatası sonrası pod'un kapanma süresi |

## 6.5 Lifecycle Hooks

Container yaşam döngüsündeki belirli anlarda tetiklenen işlemler.

### postStart
Container oluşturulduktan hemen sonra çalışır. Uyarı: başlangıç süresi garanti edilmez.

### preStop
Container sonlandırılmadan (SIGTERM gönderilmeden) önce çalışır. Bağlantıları kapatmak, load balancer'dan çıkmak için idealdir.

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo 'Container başladı' >> /var/log/startup.log"]
      preStop:
        exec:
          command: ["/bin/sh", "-c", "nginx -s quit; sleep 20"]
    terminationGracePeriodSeconds: 60   # SIGTERM → SIGKILL arasındaki süre
```

## 6.6 Termination Grace Period

Kubernetes bir pod'u silerken:
1. `SIGTERM` sinyali gönderilir (düzgün kapanma için)
2. `terminationGracePeriodSeconds` (varsayılan: **30 saniye**) beklenir
3. Süre dolunca `SIGKILL` ile zorla sonlandırılır

```yaml
spec:
  terminationGracePeriodSeconds: 120    # Büyük DB bağlantıları için artırılabilir
```

> [!IMPORTANT]
> Uzun çalışan batch işleri için `terminationGracePeriodSeconds`'ı artırın. Aksi hÃ¢lde `kubectl drain` sırasında işler yarıda kesilir.

## 6.7 Pod Disruption Budget (PDB)

Node bakımı (drain), upgrade veya auto-scale sırasında uygulamanın kaç pod'unun ayakta kalması gerektiğini belirler.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: production
spec:
  minAvailable: 2        # En az 2 pod her zaman ayakta
  # maxUnavailable: 1    # Alternatif: En fazla 1 pod kapalı olabilir
  selector:
    matchLabels:
      app: web-server
```

```bash
# PDB durumu
kubectl get pdb -n production

# Drain sırasında PDB engeli
kubectl drain worker-01 --ignore-daemonsets
# "Cannot evict pod as it would violate the pod's disruption budget"
```

> [!IMPORTANT]
> PDB yalnızca **planlı (voluntary)** kesintileri korur: `kubectl drain`, node upgrade. Donanım arızası gibi **involuntary** durumları korumaz. HA için her zaman `replicas >= 3` ve `minAvailable >= 2` kullanın.


# Pod Yaşam Döngüsü ve Probe'lar

## Pod Yaşam Döngüsü ve Durumlari (Phase)

Bir Pod, oluşturulduğu andan yok edilene kaçdar belirli bir yaşam döngüsü izler. Bu süreci anlamak, "Uygulamam neden “““çalışmıyor?”””" sorusunun cevabini bulmak için kritiktir.

### 1. Pod Fazlari (Phases)
Pod'un genel durumunun yüksek seviyeli özetidir:

| Faz | Açıklama |
|:---|:---|
| **Pending** | Pod kaçbul edildi ancak bir veya daha fazla konteyner henüz hazir degil (Imaj çççekme veya zamanlanma bekliyor). |
| **Running** | Pod bir node'a bagüçlüandi ve tüm konteynerler olusturuldu. En az bir konteyner hala çalışıyor veya baslatiliyor. |
| **Succeeded** | Pod'daki tüm konteynerler başarıyla (exit 0) sonlandi ve yeniden baslatilmayacak. |
| **Failed** | En az bir konteyner hata ile (sifir disi exit code) sonlandi. |
| **Unknown** | Pod'un durumu bilinemiyor (Genelde Node ile iletisim koptugunda görülür). |

### 2. Konteyner Durumlari (Statuses)
Pod içindeki her bir konteynerin kendi statüsü vardir:
- **Waiting:** Konteyner baslamak için gerekli islemleri (imaj çççekme, secret okuma) yürütüyor.
- **Running:** Konteyner sorunsuz sekilde çalışıyor.
- **Terminated:** Konteyner bir sebeple durdu (Basarili bitis veya hata). `kubectl describe` ile hata kodu iöncelenmelidir.

---

## Neden Probe?

Kubeürünetes, pod'un çalışıp çalışmadığını anlamak için basitçe konteyner process'inin aktif olup olmadigina bakaçr. Ancak process çalışıyor olsa bile uygulama kilitlenmis veya hazir olmayabilir. Probe'lar bu sorunu çöçöçözer.

| Probe | Amaççç | Başarısız Olunca |
|:---|:---|:---|
| **livenessProbe** | Uygulama kilitlendi mi? | Konteyner yeniden baslatilir |
| **readinessProbe** | Trafik almaya hazir mi? | Servis arkaçsindan çıkarılır |
| **startupProbe** | Uygulama basladi mi? | Diger probe'lar bekler |

## Probe Mekaçnizmalari

### 1. httpGet
Belirlenen path ve port'a HTTP istegi gönderir. 200-399 arasi dönerse sagüçlüikli kaçbul edilir.
- **host:** Bagüçlüanilacak host ismi (Varsayilan pod IP'sidir).
- **scheme:** Bagüçlüanti protokolüüü (HTTP veya HTTPS).
- **path:** Erisim sagüçlüanacak URI (ürün: `/healthz`).
- **httpHeaders:** Istege eklenecek ööözel header'lar (ürün: `Custom-Header: Awesome`).

### 2. exec
Konteyner içinde komut çalıştırır. Dönüş kodu `0` ise sagüçlüikli.

### 3. tcpSocket
Belirlenen porta TCP bagüçlüantisi açmaya çalışır. Basariliysa sagüçlüikli.

### 4. grpc (2026 eklentisi)
gRPC Health Checking Protocol' kullanir.

## Kapsamli Probe örneği

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

        # Startup Probe - uygulama tam olarak baslayana kaçdar diger probe'lari bekletir
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30   # 30 x 10s = 300 saniye max başlangıç süresi
          periodSeconds: 10

        # Liveness Probe - kilitlenmis uygulamayi yeniden baslatir
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 0    # startupProbe geçtikten sonra baslar
          periodSeconds: 15
          failureThreshold: 3       # 3 başarısızlik = pod restart

        # Readiness Probe - trafik kontrolü
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1       # 1 başarıli = hazir
          failureThreshold: 3       # 3 başarısız = servisten çıkar
```

### Exec Probe (Veritabani için)

```yaml
livenessProbe:
  exec:
    command:
    - pg_isüready
    - -U
    - postgöres
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

## Probe Parametreleri

| Parametre | Varsayilan | Açıklama |
|:---|:---:|:---|
| `initialDelaySeconds` | 0 | Ilk kontrolden önce bekleme |
| `periodSeconds` | 10 | Kontrol araligi |
| `timeoutSeconds` | 1 | Tek kontrol timeout'u |
| `successThreshold` | 1 | Sagüçlüikli sayilmak için gereken başarı sayisi |
| `failureThreshold` | 3 | Başarısız sayilmak için gereken hata sayisi |
| `terminationGracePeriodSeconds` | 30 | Probe hatasi sonrasi pod'un kaçpanma süresi |

## Lifecycle Hooks

Container yaşam döngüsündeki belirli anlarda tetiklenen islemler.

### postStart
Container olusturulduktan hemen sonra çalışır. Uyari: başlangıç süresi garanti edilmez.

### preStop
Container sonlandirilmadan (SIGTERM gönderilmeden) önce çalışır. Bagüçlüantilari kaçpatümak, load balaöncer'dan çıkmak için idealdir.

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo 'Container basladi' >> /var/log/startup.log"]
      preStop:
        exec:
          command: ["/bin/sh", "-c", "nginx -s quit; sleep 20"]
    terminationGracePeriodSeconds: 60   # SIGTERM ? SIGKILL arasindaki süre
```

## Termination Grace Period

Kubeürünetes bir pod'u silerken:
1. `SIGTERM` sinyali gönderilir (düzgün kaçpanma için)
2. `terminationGracePeriodSeconds` (varsayilan: **30 saniye**) beklenir
3. Süre dolunca `SIGKILL` ile zorla sonlandirilir

```yaml
spec:
  terminationGracePeriodSeconds: 120    # Büyük DB bagüçlüantilari için artirilabilir
```

> [!IMPORTANT]
> Uzun çalışan batch isleri için `terminationGracePeriodSeconds`'i artirin. Aksi hâlde `kubectl drain` sirasinda isler yarida kesilir.

## Pod Disruption Budget (PDB)

Node bakimi (drain), upgrade veya auto-scale sirasinda uygulamanin kaç pod'unun ayakta kaçlmasi gerektigini belirler.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: production
spec:
  minAvailable: 2        # En az 2 pod her zaman ayakta
  # maxUnavailable: 1    # Alteürünatif: En fazla 1 pod kaçpali olabilir
  selector:
    matchLabels:
      app: web-server
```

```bash
# PDB durumu
kubectl get pdb -n production

# Drain sirasinda PDB engeli
kubectl drain worker-01 --ignore-daemonsets
# "Cannot evict pod as it would violate the pod's disruption budget"
```

> [!IMPORTANT]
> PDB yalnizca **planli (voluntary)** kesintileri korur: `kubectl drain`, node upgrade. Donanim arizasi gibi **involuntary** durumlari korumaz. HA için her zaman `replicas >= 3` ve `minAvailable >= 2` kullanin.

# Pod Yasam D�ng�s� ve Probe'lar

## Pod Yasam D�ng�s� ve Durumlari (Phase)

Bir Pod, olusturuldugu andan yok edilene kadar belirli bir yasam d�ng�s� izler. Bu s�reci anlamak, "Uygulamam neden �alismiyor?" sorusunun cevabini bulmak i�in kritiktir.

### 1. Pod Fazlari (Phases)
Pod'un genel durumunun y�ksek seviyeli �zetidir:

| Faz | A�iklama |
|:---|:---|
| **Pending** | Pod kabul edildi ancak bir veya daha fazla konteyner hen�z hazir degil (Imaj �ekme veya zamanlanma bekliyor). |
| **Running** | Pod bir node'a baglandi ve t�m konteynerler olusturuldu. En az bir konteyner hala �alisiyor veya baslatiliyor. |
| **Succeeded** | Pod'daki t�m konteynerler basariyla (exit 0) sonlandi ve yeniden baslatilmayacak. |
| **Failed** | En az bir konteyner hata ile (sifir disi exit code) sonlandi. |
| **Unknown** | Pod'un durumu bilinemiyor (Genelde Node ile iletisim koptugunda g�r�l�r). |

### 2. Konteyner Durumlari (Statuses)
Pod i�indeki her bir konteynerin kendi stat�s� vardir:
- **Waiting:** Konteyner baslamak i�in gerekli islemleri (imaj �ekme, secret okuma) y�r�t�yor.
- **Running:** Konteyner sorunsuz sekilde �alisiyor.
- **Terminated:** Konteyner bir sebeple durdu (Basarili bitis veya hata). `kubectl describe` ile hata kodu incelenmelidir.

---

## Neden Probe?

Kubernetes, pod'un �alisip �alismadigini anlamak i�in basit�e konteyner process'inin aktif olup olmadigina bakar. Ancak process �alisiyor olsa bile uygulama kilitlenmis veya hazir olmayabilir. Probe'lar bu sorunu ��zer.

| Probe | Ama� | Basarisiz Olunca |
|:---|:---|:---|
| **livenessProbe** | Uygulama kilitlendi mi? | Konteyner yeniden baslatilir |
| **readinessProbe** | Trafik almaya hazir mi? | Servis arkasindan �ikarilir |
| **startupProbe** | Uygulama basladi mi? | Diger probe'lar bekler |

## Probe Mekanizmalari

### 1. httpGet
Belirlenen path ve port'a HTTP istegi g�nderir. 200-399 arasi d�nerse saglikli kabul edilir.
- **host:** Baglanilacak host ismi (Varsayilan pod IP'sidir).
- **scheme:** Baglanti protokol� (HTTP veya HTTPS).
- **path:** Erisim saglanacak URI (�rn: `/healthz`).
- **httpHeaders:** Istege eklenecek �zel header'lar (�rn: `Custom-Header: Awesome`).

### 2. exec
Konteyner i�inde komut �alistirir. D�n�s kodu `0` ise saglikli.

### 3. tcpSocket
Belirlenen porta TCP baglantisi a�maya �alisir. Basariliysa saglikli.

### 4. grpc (2026 eklentisi)
gRPC Health Checking Protocol'� kullanir.

## Kapsamli Probe �rnegi

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

        # Startup Probe - uygulama tam olarak baslayana kadar diger probe'lari bekletir
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30   # 30 x 10s = 300 saniye max baslangi� s�resi
          periodSeconds: 10

        # Liveness Probe - kilitlenmis uygulamayi yeniden baslatir
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 0    # startupProbe ge�tikten sonra baslar
          periodSeconds: 15
          failureThreshold: 3       # 3 basarisizlik = pod restart

        # Readiness Probe - trafik control�
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1       # 1 basarili = hazir
          failureThreshold: 3       # 3 basarisiz = servisten �ikar
```

### Exec Probe (Veritabani i�in)

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

### TCP Probe (Redis i�in)

```yaml
livenessProbe:
  tcpSocket:
    port: 6379
  initialDelaySeconds: 15
  periodSeconds: 20
```

## Probe Parametreleri

| Parametre | Varsayilan | A�iklama |
|:---|:---:|:---|
| `initialDelaySeconds` | 0 | Ilk kontrolden �nce bekleme |
| `periodSeconds` | 10 | Kontrol araligi |
| `timeoutSeconds` | 1 | Tek kontrol timeout'u |
| `successThreshold` | 1 | Saglikli sayilmak i�in gereken basari sayisi |
| `failureThreshold` | 3 | Basarisiz sayilmak i�in gereken hata sayisi |
| `terminationGracePeriodSeconds` | 30 | Probe hatasi sonrasi pod'un kapanma s�resi |

## Lifecycle Hooks

Container yasam d�ng�s�ndeki belirli anlarda tetiklenen islemler.

### postStart
Container olusturulduktan hemen sonra �alisir. Uyari: baslangi� s�resi garanti edilmez.

### preStop
Container sonlandirilmadan (SIGTERM g�nderilmeden) �nce �alisir. Baglantilari kapatmak, load balancer'dan �ikmak i�in idealdir.

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
    terminationGracePeriodSeconds: 60   # SIGTERM ? SIGKILL arasindaki s�re
```

## Termination Grace Period

Kubernetes bir pod'u silerken:
1. `SIGTERM` sinyali g�nderilir (d�zg�n kapanma i�in)
2. `terminationGracePeriodSeconds` (varsayilan: **30 saniye**) beklenir
3. S�re dolunca `SIGKILL` ile zorla sonlandirilir

```yaml
spec:
  terminationGracePeriodSeconds: 120    # B�y�k DB baglantilari i�in artirilabilir
```

> [!IMPORTANT]
> Uzun �alisan batch isleri i�in `terminationGracePeriodSeconds`'i artirin. Aksi hâlde `kubectl drain` sirasinda isler yarida kesilir.

## Pod Disruption Budget (PDB)

Node bakimi (drain), upgrade veya auto-scale sirasinda uygulamanin ka� pod'unun ayakta kalmasi gerektigini belirler.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: production
spec:
  minAvailable: 2        # En az 2 pod her zaman ayakta
  # maxUnavailable: 1    # Alternatif: En fazla 1 pod kapali olabilir
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
> PDB yalnizca **planli (voluntary)** kesintileri korur: `kubectl drain`, node upgrade. Donanim arizasi gibi **involuntary** durumlari korumaz. HA i�in her zaman `replicas >= 3` ve `minAvailable >= 2` kullanin.

# Troubleshooting: Pods & Containers

Pod sorunları Kubernetes'te karşılaşılan hataların büyük çoğunluğunu oluşturur. Bu bölüm, her hata durumunu **nedeninden çözümüne** kadar sistematik biçimde ele alır.

---

## İlk Adım: Hızlı Tanı

Bir pod sorun yaşadığında ilk bakılacak iki komut:

```bash
kubectl get pod <pod-adı> -n <namespace>
kubectl describe pod <pod-adı> -n <namespace>
```

`describe` çıktısında dikkat edilecek alanlar:
- **Status** — Pod'un genel durumu
- **Conditions** — Ready, PodScheduled, ContainersReady
- **Events** — En altta, gerçek hata mesajları burada

---

## CrashLoopBackOff

### Nedir?
Container sürekli çöküp yeniden başlatılıyor. Kubernetes her yeniden başlatmada bekleme süresini ikiye katlar (10s → 20s → 40s → ... → 5m). Bu duruma **Exponential Backoff** denir.

### Tanı
```bash
# Container'ın son çıkış kodunu gör
kubectl describe pod <pod> | grep -A5 "Last State"

# Çöken container'ın loglarını oku (önceki çalışmadan)
kubectl logs <pod> --previous

# Tüm container'ların logları (multi-container pod)
kubectl logs <pod> -c <container-adı> --previous
```

### Olası Nedenler ve Çözümleri

| Neden | Belirtisi | Çözüm |
|:------|:---------|:------|
| Uygulama hatası / exception | Exit code 1 | Uygulama loglarını incele |
| Yanlış başlatma komutu | `exec: not found` | `command/args` alanını düzelt |
| Eksik environment variable | Config hatası | ConfigMap/Secret bağlantısını kontrol et |
| Bağlanamadığı bağımlılık | Connection refused | Bağımlı servisin hazır olup olmadığını kontrol et |
| Hatalı liveness probe | Probe başarısız | Probe timeout/threshold değerlerini artır |

```bash
# Exit code analizi
# 0   → Başarılı çıkış (sorun yok)
# 1   → Uygulama hatası
# 137 → OOM Kill (SIGKILL — kill -9)
# 139 → Segmentation fault
# 143 → Graceful kill (SIGTERM)
# 126 → Komut çalıştırılamadı (izin sorunu)
# 127 → Komut bulunamadı
```

---

## OOMKilled (Out of Memory)

### Nedir?
Container'ın belirlenen bellek limitini aştı ve Linux kernel tarafından öldürüldü. Exit code **137** görülür.

### Tanı
```bash
kubectl describe pod <pod> | grep -A10 "OOMKilled\|OOM\|memory"

# Node düzeyinde OOM eventleri
kubectl describe node <node-adı> | grep -A5 "OOM\|MemoryPressure"

# Gerçek bellek kullanımını izle
kubectl top pod <pod> --containers
```

### Çözüm

```yaml
# resources.limits.memory değerini artır
# Önce gerçek kullanımı ölç, sonra %20 marj ekle
resources:
  requests:
    memory: "256Mi"
  limits:
    memory: "512Mi"   # OOMKilled oluyorsa artır
```

> [!WARNING]
> `limits` olmadan çalıştırmak tehlikelidir — tek bir pod node'daki tüm belleği tüketebilir ve diğer pod'ları öldürür.

> [!TIP]
> **VPA (Vertical Pod Autoscaler)** ile gerçek kaynak kullanımını otomatik ölçün: `kubectl describe vpa <vpa-name>` çıktısındaki `Recommendation` değerlerini `limits` olarak kullanın.

---

## ImagePullBackOff / ErrImagePull

### Nedir?
Kubernetes container image'ı pull edemedi.

### Tanı
```bash
kubectl describe pod <pod> | grep -A10 "Failed\|ImagePull\|registry"
```

### Olası Nedenler

```bash
# 1. Image adı/tag yanlış
# Hata: "repository does not exist"
kubectl set image deployment/<dep> <container>=nginx:1.27.99  # Yanlış tag

# 2. Private registry — imagePullSecret eksik
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass

# Pod'a secret bağla
spec:
  imagePullSecrets:
  - name: regcred

# 3. Rate limit (Docker Hub)
# Hata: "toomanyrequests: too many requests"
# Çözüm: Authenticated pull veya private mirror kullan

# 4. Network sorunu (node internete erişemiyor)
kubectl debug node/<node> -it --image=busybox -- curl https://registry-1.docker.io
```

---

## Pending (Zamanlanamıyor)

### Nedir?
Pod oluşturuldu ama henüz hiçbir node'a atanmadı. Scheduler bir node bulamıyor.

### Tanı
```bash
kubectl describe pod <pod> | grep -A20 "Events:"
# "0/3 nodes are available" mesajını ara
```

### Olası Nedenler

```bash
# 1. Yetersiz kaynak
# Hata: "Insufficient cpu" veya "Insufficient memory"
kubectl describe nodes | grep -A5 "Allocated resources"
kubectl top nodes

# 2. NodeSelector / Affinity uyumsuzluğu
# Hata: "node(s) didn't match Pod's node affinity/selector"
kubectl get nodes --show-labels
# Pod'daki nodeSelector etiketiyle karşılaştır

# 3. Taint toleration eksik
# Hata: "node(s) had untolerated taint"
kubectl describe nodes | grep Taints
# Pod'a gerekli toleration ekle

# 4. PVC bağlanamıyor (storage sorunu)
# Hata: "pod has unbound immediate PersistentVolumeClaims"
kubectl get pvc -n <namespace>
# PVC'nin Bound değil Pending durumunda olup olmadığını kontrol et
```

---

## Init Container Hataları

### Nedir?
`initContainers` bloğundaki bir container başarısız olduğunda ana container hiç başlamaz.

```bash
# Init container durumunu gör
kubectl get pod <pod>
# STATUS: Init:0/2 → 2 init container'dan 0'ı tamamlandı

# Init container logları
kubectl logs <pod> -c <init-container-adı>

# Tüm init container'ları listele
kubectl describe pod <pod> | grep -A5 "Init Containers:"
```

---

## Terminating (Silinemiyor)

### Nedir?
Pod `kubectl delete` ile silindi ama `Terminating` durumunda takılı kaldı.

```bash
# Graceful shutdown süresi dolmadan force sil
kubectl delete pod <pod> --grace-period=0 --force

# Finalizer varsa temizle
kubectl patch pod <pod> -p '{"metadata":{"finalizers":null}}'
```

> [!NOTE]
> Pod'un `terminationGracePeriodSeconds` (varsayılan 30s) içinde kapanması gerekir. Uygulama SIGTERM sinyalini handle etmiyorsa bu süre dolunca SIGKILL gönderilir.

---

## Genel Tanı Akışı

```
Pod sorunlu
     │
     ├── kubectl get pod → STATUS nedir?
     │
     ├── Pending → Scheduler sorunu (kaynak, taint, affinity)
     │
     ├── CrashLoopBackOff → kubectl logs --previous
     │         └── Exit code → OOMKilled(137), App error(1), Not found(127)
     │
     ├── ImagePullBackOff → Image adı/tag/auth sorunu
     │
     ├── Terminating → Force delete veya finalizer
     │
     └── Running ama çalışmıyor → kubectl exec ile container içine gir
               kubectl exec -it <pod> -- /bin/sh
```

---

## Container İçine Girmek (Debug)

```bash
# Çalışan container'a shell aç
kubectl exec -it <pod> -- /bin/bash
kubectl exec -it <pod> -c <container> -- /bin/sh

# Distroless/minimal image (shell yok) → Ephemeral container kullan
kubectl debug -it <pod> --image=busybox --target=<container>

# Container'ın dosya sistemini incele
kubectl exec <pod> -- ls -la /app
kubectl exec <pod> -- cat /etc/config/app.conf
kubectl exec <pod> -- env | grep DATABASE
```

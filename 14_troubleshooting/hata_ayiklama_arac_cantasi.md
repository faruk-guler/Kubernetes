# Hata Ayıklama (Debug) Araç Çantası

Kubernetes üzerinde sorun giderirken standart `kubectl get` veya `kubectl describe` komutları bazen yetersiz kalabilir. Bu rehberde, üretim ortamındaki karmaşık sorunları çözmek için kullanılan ileri seviye hata ayıklama ve teşhis (diagnostic) yöntemlerini bulabilirsiniz.

---

## 1. Ephemeral Containers ile Canlı Hata Ayıklama (`kubectl debug`)

Üretim ortamındaki imajlar genellikle güvenlik ve performans nedeniyle çok küçük tutulur (Distroless veya minimal Alpine imajlar). Bu imajlarda `sh`, `bash`, `curl` veya `ip` gibi temel araçlar bulunmaz. `kubectl debug` komutu, çalışan bir podun içine geçici bir hata ayıklama konteyneri (ephemeral container) yerleştirerek canlı debug yapmanızı sağlar.

```bash
# 1. Çalışan podun içine netshoot (ağ teşhis paketi) enjekte edin
kubectl debug -it nginx-pod \
  --image=nicolaka/netshoot \
  --target=nginx-container

# 2. Mevcut podun bir kopyasını oluşturup debug yapma
# (Orijinal pod bozulmaz, paylaşımlı işlem ağacı ile yeni bir pod oluşturulur)
kubectl debug nginx-pod -it \
  --image=ubuntu \
  --copy-to=debug-pod \
  --share-processes

# 3. İşlem bittikten sonra kopya podu silin
kubectl delete pod debug-pod
```

### Popüler Hata Ayıklama İmajları

* `nicolaka/netshoot`: curl, dig, tcpdump, iperf, netstat, bind-utils vb.
* `busybox`: Minimal shell araç seti.
* `alpine`: Hafif imaj; `apk add <paket>` ile dinamik araç yükleme olanağı.

---

## 2. Node Düzeyinde Hata Ayıklama (`kubectl debug node`)

Düğümlerin (Node) kendisine SSH erişiminizin olmadığı durumlarda, doğrudan düğüm üzerinde çalışan servisleri (kubelet, container runtime vb.) kontrol etmek için privileged container açabilirsiniz:

```bash
# Belirli bir düğüm için hata ayıklama oturumu başlatın
kubectl debug node/worker-node-1 -it --image=ubuntu

# Konteyner çalıştıktan sonra düğümün ana dosya sistemine geçin
chroot /host

# Düğüm üzerinde sistem servislerini sorgulayın
systemctl status kubelet
journalctl -u kubelet -n 100
crictl ps
```

---

## 3. `crictl` ile Container Runtime Yönetimi

Kubelet veya API Server çöktüğünde ve `kubectl` komutları yanıt vermediğinde, doğrudan host sunucuda (node) konteynerlerin durumunu kontrol etmek için `crictl` (CRI CLI) kullanılır:

```bash
# Çalışan tüm konteynerleri listeleme
crictl ps

# Durdurulmuş konteynerler dahil tümünü listeleme
crictl ps -a

# Konteyner günlüklerini (logs) görüntüleme
crictl logs <container-id>

# Çalışan podları listeleme
crictl pods

# Kullanılmayan eski imajları temizleme
crictl rmi --prune

# Konteynerin işlem ve namespace detaylarını inceleme
crictl inspect <container-id> | jq '.info.runtimeSpec.linux.namespaces'
```

---

## 4. `tcpdump` ile Ağ Trafiği Yakalama

Konteynerler arası ağ iletişiminde paket kayıpları veya hatalı protokol konuşmalarını izlemek için ağ trafiğini yakalayıp Wireshark ile inceleyebilirsiniz:

```bash
# 1. Hedef pod içine netshoot enjekte edin
kubectl debug -it target-pod --image=nicolaka/netshoot --target=target-container

# 2. netshoot shell içinde tcpdump ile trafiği yakalayın
tcpdump -i eth0 port 80 -nn -w /tmp/http_traffic.pcap

# 3. Başka bir terminalde pcap dosyasını lokal makinenize kopyalayın
kubectl cp target-pod:/tmp/http_traffic.pcap ./http_traffic.pcap

# 4. Yakalanan pcap dosyasını yerel Wireshark uygulamasında açıp analiz edin
```

---

## 5. Kubernetes Olaylarının (`Events`) İzlenmesi

Hataların kaynağını bulmada en hızlı yollardan biri küme olaylarını (Events) filtrelemektir:

```bash
# 1. Belirli bir namespace içindeki olayları zaman sırasına göre listeleme
kubectl get events -n production --sort-by='.lastTimestamp'

# 2. Sadece Warning (Hata/Uyarı) olaylarını filtreleme
kubectl get events -n production --field-selector type=Warning

# 3. Belirli bir pod ile ilgili olayları çekme
kubectl get events --field-selector involvedObject.name=target-pod

# 4. Olayları canlı (real-time) olarak izleme
kubectl get events -n production -w
```

---

## 6. Gelişmiş Log İzleme (`stern`)

Standart `kubectl logs -l app=web` komutu aynı anda çok fazla pod logunu takip ederken kararsız çalışabilir veya önceki (restarted) konteyner loglarını kaçırabilir. **Stern**, regex destekli çoklu pod log takibini kolaylaştırır:

```bash
# 1. Önceki (crashing) container günlüklerini okuma
kubectl logs crashed-pod --previous

# 2. Stern ile ad alanı genelinde log takibi (regex)
stern "web-app-.*" -n production --tail 50

# 3. Sadece belirli bir container imajına ait logları renkli gösterme
stern . -n production --container app-container
```

---

## 7. Hızlı Küme Teşhis Komutları (Cheatsheet)

Kümedeki genel durumları hızlıca taramak için kullanışlı tek satırlık (one-liner) komutlar:

```bash
# Çalışmayan/Hatalı podları hızlıca bulun
kubectl get nodes,pods -A | grep -v -E "Running|Completed"

# Kümede en çok CPU tüketen podları sıralayın
kubectl top pods -A --sort-by=cpu | head -10

# Kümede en çok bellek tüketen düğümleri (nodes) sıralayın
kubectl top nodes --sort-by=memory

# Beklemede (Pending) olan podları listeleyin
kubectl get pods -A --field-selector status.phase=Pending

# Çöken (CrashLoopBackOff) podları listeleyin
kubectl get pods -A | grep CrashLoopBackOff

# Node disk ve bellek doluluk durumlarını özetleme
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,MEMORY:.status.allocatable.memory,CPU:.status.allocatable.cpu'
```

# Düğüm (Node) Sorunlarını Giderme

Düğüm (Node) düzeyindeki sorunlar, üzerinde çalışan tüm podları ve servisleri doğrudan etkiler. Bir düğüm çöktüğünde veya kararsızlaştığında Kubernetes iş yüklerini otomatik olarak diğer düğümlere taşımaya çalışır. Ancak bu süreçte neyin ters gittiğini hızlıca teşhis etmek altyapı stabilitesi için kritiktir.

---

## 1. Düğüm Durumunu Okuma

Bir düğümün genel sağlık durumunu sorgulamak için:

```bash
# 1. Tüm düğümlerin genel durumunu listeleme
kubectl get nodes -o wide

# 2. Belirli bir düğümün detaylı durum raporunu alma
kubectl describe node <node-name>
```

`describe` çıktısında incelenmesi gereken kritik alanlar:

* **Conditions (Koşullar):** `Ready` (True olmalı), `MemoryPressure` (False olmalı), `DiskPressure` (False olmalı), `PIDPressure` (False olmalı), `NetworkUnavailable` (False olmalı).
* **Allocated resources:** Düğüme atanan toplam kaynak miktarı.
* **Events:** Düğüm düzeyinde tetiklenen son sistem hataları.

---

## 2. NotReady Durumu ve Kurtarma Yolları

Düğümün kontrol düzlemi (Control Plane) ile iletişimi koptuğunda `NotReady` durumuna düşer.

### Olası Sebep 1: Kubelet Servisi Çalışmıyor

Düğüme SSH ile bağlanıp kubelet durumunu kontrol edin:

```bash
# Kubelet servis durumunu sorgulayın
systemctl status kubelet

# Kubelet sistem günlüklerini inceleyin
journalctl -u kubelet -n 100 --no-pager

# Gerekirse servisi yeniden başlatın
systemctl restart kubelet
```

### Olası Sebep 2: Konteyner Çalışma Zamanı (CRI) Çökmüş

```bash
# Containerd servis durumunu denetleyin
systemctl status containerd

# CRI durumunu crictl ile kontrol edin
crictl ps
crictl pods

# Gerekirse çalışma zamanını yeniden başlatın
systemctl restart containerd
```

### Olası Sebep 3: API Server'a Erişim Yok (Ağ Kesintisi)

Düğümün master IP adreslerine erişip erişemediğini test edin:

```bash
curl -k https://<control-plane-ip>:6443/healthz
```

---

## 3. DiskPressure (Disk Basıncı)

Düğümün disk doluluk oranı kritik seviyeyi (genellikle %85-90) aştığında kubelet `DiskPressure` koşulunu tetikler ve podları tahliye etmeye (eviction) başlar.

```bash
# 1. Disk doluluk oranını denetleyin
df -h

# 2. Kullanılmayan konteyner imajlarını temizleyerek yer açın
crictl rmi --prune

# 3. Disk alanını en çok tüketen pod loglarını tespit edin
find /var/log/pods -name "*.log" -exec du -sh {} \; | sort -rh | head -10
```

*Not:* Sürekli çöken ve çok hızlı log üreten podlar disk doluluğunun en yaygın nedenidir. Bu podlar tespit edilip düzeltilmeli veya log rotasyonu yapılandırılmalıdır.

---

## 4. MemoryPressure (Bellek Basıncı)

Düğümdeki kullanılabilir bellek miktarı bittiğinde işletim sisteminin **OOM (Out Of Memory) Killer** mekanizması devreye girer ve rastgele konteynerleri sonlandırır.

```bash
# 1. Düğüm bellek durumunu kontrol edin
free -h
kubectl top nodes

# 2. İşletim sistemi çekirdek (kernel) loglarında OOM kayıtlarını arayın
dmesg | grep -i -E "oom|killed process"
journalctl -k | grep -i oom
```

---

## 5. Düğümü Bakıma Alma (Draining)

Bir düğüm üzerinde fiziksel bakım veya güncelleme yapmadan önce, üzerindeki podları kesintisiz şekilde diğer düğümlere taşımak için:

```bash
# 1. Düğümü yeni pod alımına kapatın (Cordon)
kubectl cordon <node-name>

# 2. Mevcut podları düğümden tahliye edin (Drain)
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60

# 3. Bakım tamamlandıktan sonra düğümü tekrar aktif edin (Uncordon)
kubectl uncordon <node-name>
```

> [!WARNING]
> `drain` işlemi, podların düzgün kapanabilmesi için tanımlanan `PodDisruptionBudget` (PDB) kurallarına sadık kalır. Eğer PDB kısıtlaması nedeniyle drain işlemi tamamlanamazsa, işlem askıda kalabilir. Gerekirse `--force` parametresi ile zorlanabilir ancak bu durum canlı sistemlerde kesintiye yol açabilir.

---

## 6. Genel Düğüm Teşhis Akış Şeması

```
[ DÜĞÜM SORUNU TESPİT EDİLDİ ]
        │
        ├──► NotReady ise?
        │     ├──► Kubelet servisini kontrol et (systemctl status kubelet)
        │     ├──► CRI (containerd) durumunu denetle
        │     └──► Master API Server bağlantısını sorgula (curl)
        │
        ├──► DiskPressure ise?
        │     ├──► 'df -h' ile hangi diskin dolduğunu bul
        │     ├──► 'crictl rmi --prune' ile eski imajları sil
        │     └──► Pod log klasörlerini (/var/log/pods) temizle
        │
        └──► MemoryPressure ise?
              ├──► 'kubectl top pods' ile en çok tüketen podu bul
              └──► Çekirdek loglarında (dmesg) OOM kayıtlarını incele
```

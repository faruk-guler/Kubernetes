# Depolama (Storage) Sorunlarını Giderme

Kubernetes üzerinde depolama sorunları genellikle sessizce ortaya çıkar. Podlar `ContainerCreating` durumunda takılı kalabilir, PVC'ler (PersistentVolumeClaim) sonsuza kadar `Pending` durumunda bekleyebilir veya çalışan bir uygulama diske veri yazamadığı için çökebilir. Bu rehberde, depolama katmanındaki sorunları nasıl teşhis ve tamir edeceğinizi bulabilirsiniz.

---

## 1. PVC 'Pending' Durumunda Kaldı (Bound Olmama Sorunu)

Yeni bir PVC oluşturulmasına rağmen `Bound` durumuna geçmiyorsa, aşağıdaki adımlarla sorunu daraltın:

```bash
# 1. PVC durumunu sorgulayın
kubectl get pvc -n production

# 2. PVC olaylarını (Events) detaylıca inceleyin
kubectl describe pvc <pvc-name> -n production
```

### Olası Nedenler ve Çözümler

#### A. Belirtilen StorageClass Mevcut Değil

```bash
# Kümedeki StorageClass listesini çekin
kubectl get storageclass

# PVC içindeki storageClassName alanını kontrol edin ve kümedekilerle karşılaştırın
kubectl get pvc <pvc-name> -o jsonpath='{.spec.storageClassName}'
```

*Çözüm:* Eğer `storageClassName` boşsa, kümede bir varsayılan (default) StorageClass tanımlı olmalıdır. Varsayılan sınıfı ayarlamak için:

```bash
kubectl patch storageclass <sc-name> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

#### B. WaitForFirstConsumer (Bekleme Modu) Etkinliği

```bash
kubectl get sc <sc-name> -o jsonpath='{.volumeBindingMode}'
# Çıktı "WaitForFirstConsumer" ise -> Bu bir hata değildir!
# PVC, ona bağlı olan Pod bir düğüme zamanlanana kadar (Scheduled) Pending durumunda bekler.
```

#### C. CSI Driver veya Provisioner Pod'ları Çalışmıyor

CSI eklentisi (Longhorn, AWS EBS CNI vb.) çökmüşse dinamik PV oluşturulamaz:

```bash
# CSI sürücü podlarının durumunu kontrol edin
kubectl get pods -A | grep -i -E "csi|longhorn|aws-ebs|nfs"
```

---

## 2. Volume Mount (Birim Bağlama) Hataları

Pod, `ContainerCreating` durumunda takılı kalıyor ve `describe` çıktısında `Unable to attach or mount volumes` hatası alıyorsa:

```bash
kubectl describe pod <pod-name> -n production
```

### Olası Hatalar ve Çözümleri

#### A. Multi-Attach Hatası (ReadWriteOnce)

*Hata Mesajı:* `Multi-Attach error for volume ... Volume is already exclusively attached to one node`
*Neden:* `ReadWriteOnce` (RWO) erişim modundaki bir disk, fiziksel olarak başka bir düğümdeki (Node) pod tarafından kilitlenmiştir. Eski pod silinmesine rağmen disk düğümden detach (ayrılma) edilememiştir.
*Çözüm:* Kilitli düğümü ve eski podu bulup zorla sonlandırın:

```bash
kubectl delete pod <old-pod-name> --grace-period=0 --force
```

#### B. NFS veya Dış Depolama Bağlantı Hatası

Eğer NFS mount işlemi başarısız oluyorsa düğümler üzerine NFS istemci paketleri (`nfs-common`) kurulmamış olabilir:

```bash
# Node üzerinde kontrol edin (SSH ile)
mount -t nfs <nfs-server-ip>:/export /mnt/test
```

---

## 3. Diskin Tamamen Dolması (No Space Left on Device)

Pod içindeki uygulamanın diski doldurması veya logların şişmesi durumunda:

```bash
# 1. Konteyner içindeki disk doluluk oranını denetleyin
kubectl exec -it <pod-name> -n production -- df -h

# 2. PVC kapasitesini kontrol edin
kubectl get pvc <pvc-name> -n production
```

### Çözüm Yolu (Volume Expansion - Disk Genişletme)

Eğer kullandığınız StorageClass disk genişletmeyi destekliyorsa (`allowVolumeExpansion: true`), PVC boyutunu dinamik olarak artırabilirsiniz:

```bash
# PVC boyutunu 10Gi'den 20Gi'ye yamalayın
kubectl patch pvc <pvc-name> -n production -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

*Not:* Genişleme işlemi pod çalışmaya devam ederken veya pod yeniden başladığında (CSI sürücüsüne bağlı olarak) aktif hale gelir.

---

## 4. Released PV'lerin Yeniden Kullanılması (Reclaim Policy)

PVC silinmesine rağmen ilişkili PV `Released` durumunda kalıyor ve yeni bir PVC tarafından kullanılamıyorsa:

```bash
kubectl get pv
# STATUS: Released
```

Eğer PV reclaim policy `Retain` olarak ayarlanmışsa, veri güvenliği için disk otomatik temizlenmez. Diski sıfırlayıp tekrar kullanılabilir hale getirmek için claim referansını manuel olarak temizlemeniz gerekir:

```bash
# claimRef değerini null yaparak PV'yi boşa çıkartın
kubectl patch pv <pv-name> -p '{"spec":{"claimRef":null}}'
```

---

## 5. Genel Depolama Teşhis Akış Şeması

```
[ DEPOLAMA (STORAGE) SORUNU ]
        │
        ├──► PVC 'Pending' durumunda?
        │     ├──► StorageClass adını kontrol et (kubectl get sc)
        │     ├──► CSI driver pod'larını kontrol et (longhorn/ebs vb.)
        │     └──► 'volumeBindingMode' WaitForFirstConsumer mı bak
        │
        ├──► Pod 'ContainerCreating' durumunda takılı?
        │     ├──► 'Multi-Attach' hatası var mı (RWO kilitlenme)?
        │     └──► Düğümler üzerinde NFS istemcileri kurulu mu denetle
        │
        └──► Uygulama 'No Space Left' hatası veriyor?
              ├──► StorageClass 'allowVolumeExpansion' destekliyor mu bak
              └──► PVC boyutunu yaml üzerinden yamala (patch) ve büyüt
```

# PV, PVC ve StorageClass

`emptyDir` veya `hostPath` gibi geçici (ephemeral) depolama yöntemleri, podun yaşam süresine bağlı olarak çalışır. Pod silindiğinde veya başka bir düğüme (node) taşındığında veriler kaybolur. Kalıcı veri depolama ihtiyacını çözmek için Kubernetes bizlere **PersistentVolume (PV)** ve **PersistentVolumeClaim (PVC)** mekanizmalarını sunmaktadır.

---

## Kalıcı Depolama Sorunu ve Çözüm Arayışı

Depolama ihtiyacını daha iyi anlamak için gerçek bir senaryo üzerinden gidelim:

* **Senaryo:** 3 node'lu bir Kubernetes cluster'ımız olduğunu ve üzerinde tek replikalı (single pod) bir MySQL veritabanı çalıştırmak istediğimizi varsayalım. Veritabanının dosyalarını saklamak için pod tanımında `emptyDir` türünde geçici bir volume oluşturup container'a mount ettik.
* **İlk Durum:** Podumuz uygun bir worker node üzerinde başarılı şekilde çalışmaya başladı. MySQL container'ında bir çökme yaşanırsa kubelet onu aynı node üzerinde yeniden başlatır ve `emptyDir` silinmediği için veriler korunur.
* **Sorun:** Ancak podun çalıştığı worker node fiziksel veya donanımsal bir arıza nedeniyle çökerse ne olur? Pod bir Deployment nesnesinin parçası olduğu için Kubernetes durumu düzeltmek amacıyla podu sağlıklı olan başka bir worker node üzerinde yeniden oluşturur.
* **Veri Kaybı:** MySQL podu yeni node üzerinde ayağa kalktığında `emptyDir` de o yeni node üzerinde sıfırdan oluşturulur. Eski node üzerindeki diske erişim koptuğu için veritabanındaki tüm verilerimiz kaybolur. Bu, üretim (production) ortamları için kabul edilemez bir felakettir.

**Çözüm:** Bu sorunun tek çözümü, depolama alanını (volume) cluster'ın worker node'larından bağımsız, harici bir depolama ünitesinde (SAN, NAS, Cloud Storage vb.) oluşturmak ve tüm node'ların bu ortak alana erişebilmesini sağlamaktır. Böylece pod hangi node'a taşınırsa taşınsın, aynı harici depolama birimine tekrar bağlanabilir ve veri devamlılığı sağlanır. Kubernetes'te pod yaşam döngüsünden bağımsız bu kalıcı depolama birimlerine **Persistent Volume (PV)** denir.

---

## Container Storage Interface (CSI) ve Sürücüler

Kubernetes'in bu harici depolama birimleriyle haberleşebilmesi için ilgili depolama sisteminin sürücülerine (volume driver) ihtiyacı vardır.

Kubernetes, NFS veya iSCSI gibi evrensel protokollerin yanı sıra AWS EBS, Azure Disk, Google Persistent Disk gibi büyük bulut sağlayıcılarının sürücülerini varsayılan olarak içinde barındırır. Ancak depolama teknolojileri bunlarla sınırlı değildir. Farklı depolama çözümleriyle genişletilebilir bir yapıda çalışmak için **Container Storage Interface (CSI)** standardı geliştirilmiştir.

CSI, depolama üreticilerinin (örneğin NetApp, Dell EMC, Ceph, Longhorn) Kubernetes çekirdek koduna dokunmak zorunda kalmadan, kendi sistemlerini Kubernetes cluster'ına entegre edebilecekleri sürücüler yazmalarını sağlar. Eğer yerleşik desteklenenler dışında üçüncü parti bir depolama ürünü kullanıyorsanız, ilgili üreticinin CSI sürücüsünü cluster'a yüklemeniz gerekir.

---

## PersistentVolume (PV) — Kalıcı Depolama Alanı

Persistent Volume (PV), sistem yöneticileri tarafından manuel olarak veya StorageClass aracılığıyla otomatik olarak oluşturulan gerçek depolama alanını temsil eder.

Aşağıda, harici bir NFS sunucusu üzerinde oluşturulan depolama alanını Kubernetes'e tanıtan örnek bir PV manifestosu yer almaktadır:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-static-pv
  labels:
    app: mysql-storage
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /var/nfs/data
    server: 172.17.0.2
```

### PV Parametrelerinin Anlamı

* **capacity:** Yaratılacak veya ayrılacak depolama alanının boyutunu belirtir (Örn: `5Gi`).
* **accessModes:** Depolama biriminin pod'lar tarafından nasıl bağlanacağını belirler:
    * **ReadWriteOnce (RWO):** Volume aynı anda sadece tek bir node tarafından okuma/yazma modunda bağlanabilir.
    * **ReadOnlyMany (ROX):** Volume aynı anda birden fazla node tarafından sadece okuma (read-only) modunda bağlanabilir.
    * **ReadWriteMany (RWX):** Volume aynı anda birden fazla node tarafından okuma/yazma modunda bağlanabilir (Örn: NFS).
    * **ReadWriteOncePod (RWOP):** Kubernetes 1.22+ ile gelen bu mod, volume'ün tüm cluster'da sadece tek bir pod tarafından bağlanabilmesini garanti eder.
* **persistentVolumeReclaimPolicy:** Pod'un işi bittiğinde ve PVC silindiğinde arkada kalan PV verisine ne olacağını belirler:
    * **Retain:** Volume içindeki veriler ve PV korunur. Yönetici verileri manuel olarak kurtarabilir veya silebilir.
    * **Recycle (Deprecated):** Volume içindeki tüm dosyalar silinir (`rm -rf`) ve PV yeniden kullanıma hazır hale getirilir. Kubernetes 1.15+ itibarıyla kullanımdan kaldırılmıştır (deprecated/removed), yeni projelerde kullanılmamalıdır.
    * **Delete:** PV objesi ve arkasındaki gerçek bulut depolama birimi (AWS EBS vb.) tamamen silinir.

---

## PersistentVolumeClaim (PVC) — Depolama Talebi

Geliştiriciler (developer), pod'larına doğrudan bir PersistentVolume bağlayamazlar. Bunun yerine, cluster'da bulunan mevcut PV'ler arasından kendi ihtiyaçlarına uygun olanı talep etmek için bir **PersistentVolumeClaim (PVC)** objesi oluştururlar.

Aşağıda, yukarıda oluşturduğumuz NFS PV'yi etiket (label) üzerinden talep eden bir PVC örneği bulunmaktadır:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  selector:
    matchLabels:
      app: mysql-storage
```

---

## Neden İki Farklı Obje? (Rollerin Ayrılması)

Kubernetes'in depolama alanını tanımlama (PV) ve talep etme (PVC) olarak ikiye bölmesinin çok önemli bir nedeni vardır: **Cluster Yöneticisi (Admin) ile Uygulama Geliştiricisi (Developer) rollerinin ayrılması.**

* **Yönetici Rolü (PV):** Cluster'ı yöneten sistem yöneticisi depolama donanımına (AWS EBS, NFS, Ceph vb.) erişebilir durumdadır. Depolama ünitesinde alanlar oluşturur ve bunların Kubernetes'teki karşılığı olan PV'leri yazar. Geliştiricinin donanım detaylarını (NFS IP'si veya disk ID'si gibi hassas bilgileri) bilmesini istemez.
* **Geliştirici Rolü (PVC):** Uygulamayı geliştiren kişi donanımdan bağımsız olarak sadece "Bana 5GB boyutunda, okuma/yazma yapabileceğim bir alan lazım" der ve PVC oluşturur. Kubernetes, bu talebi arka planda uygun bir PV ile otomatik olarak eşleştirir (Binding).
* **Taşınabilirlik:** Bu ayrım sayesinde uygulamanızın YAML dosyaları (PVC ve Pod tanımları) taşınabilir hale gelir. Aynı PVC tanımını kendi lokal Kubernetes cluster'ınızda NFS ile karşılarken, hiç değiştirmeden AWS ortamına götürüp EBS ile karşılayabilirsiniz.

---

## Dinamik Depolama ve StorageClass

Büyük cluster'larda sistem yöneticilerinin geliştiricilerin her talebi için manuel olarak PV oluşturması pratik değildir. Bu sorunu çözmek için **StorageClass** yapısı kullanılır. StorageClass, geliştirici PVC oluşturduğu anda arka planda otomatik olarak (on-demand) PV oluşturulmasını sağlayan bir şablondur.

### Longhorn StorageClass (Bare Metal)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-replicated
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  numberOfReplicas: "3"
  diskSelector: "ssd"
```

### AWS EBS / GCP PD StorageClass (Bulut)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer   # Pod schedule olana kadar disk oluşturma
allowVolumeExpansion: true
parameters:
  type: gp3
```

---

## Volume Genişletme ve Anlık Yedekleme (Snapshot)

### Volume Genişletme (Volume Expansion)

Kapasitesi dolan bir PVC'nin boyutunu online olarak artırabilirsiniz:

```bash
# PVC boyutunu patch ile 50Gi'ye yükseltme
kubectl patch pvc mysql-pvc -n production -p \
  '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

> [!IMPORTANT]
> Genişletmenin çalışabilmesi için kullanılan StorageClass üzerinde `allowVolumeExpansion: true` parametresinin tanımlanmış olması gerekir.

### VolumeSnapshot ile Yedekleme

```yaml
# 1. Mevcut PVC'den anlık snapshot alma
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mysql-db-backup
  namespace: production
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: mysql-pvc
```

```yaml
# 2. Snapshot'tan geri dönerek yeni bir PVC oluşturma
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-restored-pvc
spec:
  dataSource:
    name: mysql-db-backup
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

---

## Uygulamalı Örnek: NFS Sunucu ve Manuel PV Kurulumu

Dinamik depolama sağlayıcısının bulunmadığı bare-metal veya lokal ortamlarda en yaygın yöntem harici bir NFS sunucusu kurmaktır.

### 1. NFS Sunucusu Hazırlığı (NFS Host Üzerinde)

```bash
# NFS paketlerini yükleyin
sudo apt update && sudo apt install nfs-kernel-server -y

# Paylaşım dizinini oluşturun ve yetkilendirin
sudo mkdir -p /nfs/kubedata/projeler
sudo chown nobody:nogroup /nfs/kubedata/projeler
sudo chmod 777 /nfs/kubedata/projeler

# Dizin paylaşım yetkilerini /etc/exports dosyasına ekleyin
# Örn: /nfs/kubedata/projeler *(rw,sync,no_subtree_check,no_root_squash)
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

### 2. Worker Node Hazırlığı (Tüm Node'larda)

```bash
# Kubernetes worker node'larının NFS ile konuşabilmesi için istemci paketi kurulmalıdır
sudo apt install nfs-common -y
```

### 3. NFS PV ve PVC Eşleştirmesi

Kalıcı depolama alanını oluşturup talep ettikten sonra pod içerisinde şu şekilde mount ederek kullanabilirsiniz:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mysql-pod
  namespace: production
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: "supersecretpassword"
    volumeMounts:
    - name: mysql-persistent-storage
      mountPath: /var/lib/mysql
  volumes:
  - name: mysql-persistent-storage
    persistentVolumeClaim:
      claimName: mysql-pvc
```

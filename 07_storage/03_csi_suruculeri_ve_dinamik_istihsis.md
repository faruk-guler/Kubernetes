# CSI Sürücüleri ve Dinamik Disk Yönetimi (CSI Drivers & Dynamic Provisioning)

**CSI (Container Storage Interface)**, Kubernetes'in depolama (storage) sistemleriyle konuşmasını standartlaştıran açık bir arayüzdür. 2019 yılından itibaren Kubernetes, çekirdek kodunun içinde yer alan tüm eski yerleşik (in-tree) depolama sürücülerini (AWS EBS, Ceph vb.) kaldırarak harici **CSI Sürücüsü (CSI Driver)** modeline taşımıştır. Bu sayede depolama üreticileri, Kubernetes çekirdeğinin güncellenmesini beklemeden kendi sürücülerini bağımsız olarak geliştirebilmektedir.

---

## 1. CSI Mimarisi ve Çekirdek Bileşenleri

CSI mimarisi, küme düzeyinde çalışan bir denetleyici (Controller) ve her düğümde koşan bir ajan (Node Plugin) olmak üzere iki ana parçadan oluşur:

```
                  [ Kubernetes API Server ]
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
[ CSI Controller Plugin ]           [ CSI Node Plugin ]
  (Deployment - Kümede 1 Adet)        (DaemonSet - Her Düğümde)
  ├── CreateVolume / DeleteVolume     ├── NodePublishVolume (mount)
  ├── AttachVolume / DetachVolume     └── NodeUnpublishVolume (unmount)
  └── CreateSnapshot / DeleteSnapshot
```

* **CSI Controller Plugin:** Depolama alanlarının oluşturulması, silinmesi ve disklerin sanal sunuculara (VM/Node) fiziksel olarak takılması/çıkarılması (Attach/Detach) işlemlerini yöneten merkezi birimdir.
* **CSI Node Plugin:** Her düğümde (`DaemonSet` olarak) çalışır. Takılan diskin ilgili podun dosya sistemi içine bağlanmasını (Mount/NodePublishVolume) ve pod silindiğinde güvenle çözülmesini (Unmount) üstlenir.

---

## 2. Dinamik Disk Tahsis Süreci (Dynamic Provisioning Flow)

Geliştiricilerin manuel olarak disk oluşturup bunu podlara bağlama zahmetini ortadan kaldıran dinamik disk tahsis süreci şu adımlarla gerçekleşir:

```
1. Geliştirici bir PVC (PersistentVolumeClaim) oluşturur.
         │
         ▼
2. Kubernetes, PVC içindeki StorageClass tanımlayıcısını kontrol eder.
         │
         ▼
3. Kubernetes, ilgili depolama sağlayıcısının CSI Controller eklentisine "CreateVolume" çağrısı gönderir.
         │
         ▼
4. CSI Controller, bulut sağlayıcısında (AWS EBS vb.) veya yerel depolama havuzunda diski oluşturur.
         │
         ▼
5. PV (PersistentVolume) otomatik üretilir ve PVC'ye bağlanır (Bound).
         │
         ▼
6. Pod, diskin takıldığı düğüme schedule edildiğinde, o düğümdeki CSI Node Plugin diski işletim sistemine bağlar (Mount/NodePublishVolume).
```

---

## 3. Popüler CSI Sürücüleri ve Kurulumu

### A. Longhorn (Kubernetes-Native Dağıtık Blok Depolama)

SUSE tarafından geliştirilen, worker düğümlerindeki yerel diskleri birleştirerek yedekli disk havuzları oluşturan kurumsal standarttır.

```bash
# 1. Her worker düğümünde open-iscsi yüklü olmalıdır
apt install open-iscsi -y

# 2. Helm ile kurulum
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
```

### B. NFS CSI Driver (Paylaşımlı RWX Depolama)

NFS sunucularınızı Kubernetes'e dinamik depolama sağlayıcısı olarak entegre etmek için en hafif ve yaygın yöntemdir:

```bash
# Helm ile kurulum
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system
```

---

## 4. CSI Durum Sorgulama Komutları

```bash
# Kümeye kurulu CSI sürücülerini listelemek için:
kubectl get csidriver

# Düğümlerin CSI eklenti durumlarını görmek için:
kubectl get csinode

# Düğümlere takılı fiziksel disklerin (attachment) durumunu incelemek için:
kubectl get volumeattachments
```

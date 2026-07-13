# etcd Yedekleme ve Geri Yükleme (etcd Backup & Restore)

**etcd**, Kubernetes kümesinin (cluster) beynidir. Tüm yapılandırma (YAML tanımları), sırlar (Secrets), konfigürasyonlar (ConfigMaps), RBAC kuralları ve çalışan podların durum bilgileri (state) bu anahtar-değer (Key-Value) veritabanında saklanır.

etcd veritabanı olmadan çöken bir Kubernetes kümesini kurtarmak imkansızdır. Bu nedenle, düzenli ve güvenli etcd yedeklemesi yapmak, küme yönetiminin en hayati operasyonudur.

---

## 1. etcd Sağlık Kontrolü (kubeadm)

kubeadm ile kurulan kümelerde etcd, master düğümlerde birer statik pod olarak çalışır. Durumunu kontrol etmek için:

```bash
# 1. etcd pod adını öğrenin
kubectl get pods -n kube-system -l component=etcd

# 2. etcdctl ile etcd sağlık durumunu sorgulayın
kubectl exec -n kube-system etcd-k8s-master-01 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  endpoint health
```

---

## 2. Manuel Yedek (Snapshot) Alma

Sertifika yolları kubeadm standartlarında `/etc/kubernetes/pki/etcd/` altındadır. Master düğümünde yerel olarak yedek almak için `etcdctl` CLI aracı kullanılır:

```bash
# etcdctl API sürümünü 3 olarak set edin
export ETCDCTL_API=3

# Snapshot dosyasını kaydedin
sudo etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db
```

### Snapshot Dosyasının Doğrulanması

Yedeğin bozuk olmadığını (integrity) kontrol etmek için status komutu çalıştırılır:

```bash
etcdctl --write-out=table snapshot status /backup/etcd-xxxx.db
# Çıktıda HASH, REVISION, TOTAL KEYS ve TOTAL SIZE değerlerinin dolu olması gerekir.
```

---

## 3. Otomatik Zamanlanmış Yedekleme (Kubernetes CronJob)

Aşağıdaki manifest, her gün gece yarısı etcd yedeği alıp bunu host üzerindeki `/backup` dizinine yazan güvenli bir Kubernetes CronJob şablonudur:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [etcd_yedekleme_ve_geri_yukleme_manifest_1.yaml](../Manifests/04_infrastructure/etcd_yedekleme_ve_geri_yukleme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Standart Geri Yükleme (Restore) Prosedürü

> [!CAUTION]
> Geri yükleme (Restore) işlemi kümedeki API Server'ı kilitler ve tüm pod akışlarını durdurur. Canlı (production) ortamda denemeden önce mutlaka test kümelerinde pratik yapınız.

### Adım 1: Control Plane Bileşenlerini Durdurun

Kubelet'in etcd ve API Server podlarını kapatması için statik pod manifest dosyalarını geçici olarak klasör dışına taşıyın:

```bash
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
# Podların kapandığından emin olmak için docker/containerd üzerinde kontrol yapabilirsiniz.
```

### Adım 2: Restore İşlemini Tetikleyin

Snapshot dosyasını yeni bir etcd veri dizinine (`/var/lib/etcd-from-backup`) açın:

```bash
sudo ETCDCTL_API=3 etcdctl \
  --data-dir=/var/lib/etcd-from-backup \
  snapshot restore /backup/etcd-20260402-140000.db
```

### Adım 3: etcd Manifest Dosyasını Yeni Dizine Göre Güncelleyin

`/tmp/etcd.yaml` dosyasını açarak eski `/var/lib/etcd` yollarını `/var/lib/etcd-from-backup` ile değiştirin:

```bash
# Veya sed kullanarak otomatik değiştirin:
sudo sed -i 's|/var/lib/etcd|/var/lib/etcd-from-backup|g' /tmp/etcd.yaml
```

### Adım 4: Manifestleri Geri Taşıyarak Servisleri Başlatın

```bash
sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# Kubelet'i tetikleyin
sudo systemctl restart kubelet
```

---

## 5. RKE2 Özel etcd Operasyonları

Rancher RKE2, yerleşik etcd komut setlerine sahiptir ve yedekleri otomatik olarak `/var/lib/rancher/rke2/server/db/snapshots/` altında saklar.

```bash
# 1. RKE2 CLI ile anlık manuel yedek alma
rke2 etcd-snapshot save --name pre-upgrade-backup

# 2. Kayıtlı yedekleri listeleme
rke2 etcd-snapshot ls

# 3. RKE2 Servisini tüm düğümlerde durdurun
systemctl stop rke2-server

# 4. Yedeği belirtip cluster'ı resetleyerek geri yükleyin
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/pre-upgrade-backup

# 5. RKE2 servisini sadece ilk master'da başlatın
systemctl start rke2-server
```

---

## Özet

etcd yedeklemesi, felaket anında hayatta kalmanızı sağlayan tek sigortadır. **etcdctl** ile alınan snapshot'lar, API Server ve etcd statik podları durdurularak güvenli bir şekilde geri yüklenebilir. **CronJob** yardımıyla günlük olarak harici bir storage birimine (NFS, S3 vb.) yedek aktarımı yapılması kurumsal standartların vazgeçilmezidir.

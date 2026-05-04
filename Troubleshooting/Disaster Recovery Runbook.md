# Disaster Recovery Runbook

Bu runbook, Kubernetes cluster'ında yaşanan kritik arızalarda adım adım uygulanacak kurtarma prosedürlerini içerir. Her senaryo için hazır komutlar sunulmuştur.

---

## DR Önce: Hazırlık Kontrol Listesi

```bash
# Haftalık kontroller (cron ile otomatize et)

# 1. etcd backup
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db
# → S3'e yükle

# 2. Velero backup
velero backup create weekly-$(date +%Y%m%d) \
  --include-namespaces production,staging \
  --ttl 720h

# 3. Sertifika son kullanma tarihleri
kubeadm certs check-expiration

# 4. etcd üyelerini kontrol et
etcdctl member list

# 5. Cluster durumu
kubectl get nodes
kubectl get pods -A | grep -v Running
```

---

## Senaryo 1: Pod CrashLoopBackOff

```bash
# Teşhis
kubectl get pod <pod> -n <ns>
kubectl describe pod <pod> -n <ns> | tail -20
kubectl logs <pod> -n <ns> --previous

# Olası nedenler ve çözümler:
# a) OOMKill → memory limit çok düşük
kubectl top pod <pod> -n <ns>
kubectl set resources deployment/<dep> -c=<container> \
  --limits=memory=512Mi -n <ns>

# b) Config hatası → env/secret yanlış
kubectl get secret <secret> -n <ns> -o jsonpath='{.data}' | base64 -d

# c) Readiness probe başarısız → endpoint yanlış
kubectl describe pod <pod> -n <ns> | grep -A10 "Readiness"

# d) Image pull hatası
kubectl describe pod <pod> -n <ns> | grep "image"
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io \
  --docker-username=<user> \
  --docker-password=<token>
```

---

## Senaryo 2: Node NotReady

```bash
# Teşhis
kubectl get nodes
kubectl describe node <node> | grep -A20 "Conditions:"
kubectl describe node <node> | grep -A10 "Events:"

# Node'a SSH gir
ssh user@<node-ip>

# Kubelet kontrolü
systemctl status kubelet
journalctl -u kubelet -n 50 --no-pager

# Disk dolu mu?
df -h
# Çözüm: Docker/containerd image temizliği
crictl rmi --prune
du -sh /var/lib/containerd/ /var/log/

# Bellek baskısı mı?
free -h
# Çözüm: Pod'ları tahliye et
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Kubelet yeniden başlat
systemctl restart kubelet

# Node geri döndüğünde
kubectl uncordon <node>
```

---

## Senaryo 3: etcd Quorum Kaybı

### 3a: Tek etcd node arızası (3 node'dan 1'i)

```bash
# Sağlıklı etcd'yi kontrol et
ETCD_OPTS="--endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key"

etcdctl $ETCD_OPTS member list
etcdctl $ETCD_OPTS endpoint health

# Arızalı üyeyi çıkar
etcdctl $ETCD_OPTS member remove <member-id>

# Yeni etcd node'u ekle
etcdctl $ETCD_OPTS member add etcd-new \
  --peer-urls=https://192.168.1.103:2380

# Yeni node'da etcd başlat (--initial-cluster-state=existing ile)
```

### 3b: Tam etcd kaybı — snapshot restore

```bash
# Son snapshot'ı S3'ten al
aws s3 cp s3://company-backups/etcd/etcd-20260425.db /tmp/etcd-backup.db

# Snapshot bütünlüğünü doğrula
etcdctl snapshot status /tmp/etcd-backup.db

# etcd'yi geri yükle (tüm control plane'lerde)
# ÖNCE: API server ve etcd pod'larını durdur
mkdir /etc/kubernetes/manifests-backup
mv /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/manifests-backup/
mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests-backup/

# Mevcut etcd verisini yedekle
mv /var/lib/etcd /var/lib/etcd-bak

# Restore et
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --name master-1 \
  --initial-cluster "master-1=https://192.168.1.100:2380" \
  --initial-advertise-peer-urls https://192.168.1.100:2380 \
  --data-dir /var/lib/etcd

# etcd manifest'ini geri getir
mv /etc/kubernetes/manifests-backup/etcd.yaml /etc/kubernetes/manifests/
mv /etc/kubernetes/manifests-backup/kube-apiserver.yaml /etc/kubernetes/manifests/

# Cluster durumunu kontrol et
kubectl get nodes
kubectl get pods -A
```

---

## Senaryo 4: API Server Erişim Yok

```bash
# API Server pod'u çalışıyor mu?
crictl ps | grep apiserver

# Static manifest kontrol
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep "advertise-address"

# API Server logları
crictl logs <apiserver-container-id>

# En yaygın nedenler:
# a) etcd'ye bağlanamıyor → etcd sertifikası süresi dolmuş
ls -la /etc/kubernetes/pki/etcd/

# b) Sertifika süresi dolmuş
kubeadm certs renew all
systemctl restart kubelet

# c) Yanlış flag → manifest bozuk
# Doğru YAML için:
kubeadm init phase control-plane apiserver
```

---

## Senaryo 5: Sertifika Süresi Dolmuş

```bash
# Kontrol
kubeadm certs check-expiration

# Tüm sertifikaları yenile
kubeadm certs renew all

# Kubelet yeniden başlat
systemctl restart kubelet

# Admin kubeconfig güncelle
cp /etc/kubernetes/admin.conf ~/.kube/config
kubectl get nodes   # Çalışıyor mu?

# kubeconfig kopyasını dağıt
for user in ubuntu admin deployer; do
  cp /etc/kubernetes/admin.conf /home/$user/.kube/config
  chown $user:$user /home/$user/.kube/config
done
```

---

## Senaryo 6: Velero ile Namespace Restore

```bash
# Mevcut backup'ları listele
velero backup get

# Belirli namespace'i restore et
velero restore create \
  --from-backup weekly-20260425 \
  --include-namespaces production \
  --namespace-mappings production:production-restored

# Restore durumu
velero restore get
velero restore describe <restore-name> --details

# Başarısız restore'u debug et
velero restore logs <restore-name>
```

---

## Senaryo 7: Tüm Cluster Yok — Yeni Cluster'a Taşı

```bash
# 1. Yeni cluster kur (kubeadm/talos/rke2)
# 2. Velero'yu yeni cluster'a kur ve aynı storage backend'i göster
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set configuration.backupStorageLocation[0].bucket=company-backups \
  --set configuration.backupStorageLocation[0].config.region=eu-west-1

# 3. Backup'ları keşfet (önceki cluster'dan)
velero backup-location get

# 4. Tüm namespace'leri restore et
velero restore create full-restore \
  --from-backup weekly-20260425

# 5. DNS'i yeni cluster'a güncelle
# LoadBalancer IP değişti → DNS kayıtlarını güncelle
kubectl get svc -A | grep LoadBalancer
```

---

## DR Test Takvimi

| Frekans | Test | Tahmini Süre |
|:--------|:-----|:-------------|
| **Haftalık** | Velero backup başarı kontrolü | 5 dakika |
| **Aylık** | Velero restore — staging namespace | 30 dakika |
| **Çeyreklik** | etcd snapshot restore — test cluster | 2 saat |
| **Yıllık** | Tam cluster yeniden yapılandırma | 1 gün |

> [!CAUTION]
> DR testlerini **her zaman test ortamında** yapın. Production'da etcd restore denerken gerçek veri kaybı yaşanabilir. Test sonuçlarını belgeleyin ve RTO/RPO hedeflerinizle karşılaştırın.

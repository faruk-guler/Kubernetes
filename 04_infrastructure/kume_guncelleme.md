# Kubernetes Küme Sürüm Yükseltme (Cluster Upgrade)

Kubernetes küme yükseltme (upgrade) işlemi, doğru planlanmadığında çalışan tüm canlı (production) sistemlerin durmasına yol açabilecek riskli bir operasyondur.

Bu bölümde, güvenli bir sürüm yükseltme stratejisini, sürüm kontrol ve hazırlık adımlarını, **kubeadm** ile Master ve Worker düğümlerinin adım adım güncellenmesini ve olası bir hata anında kurtarma (rollback) planlarını ele alacağız.

---

## 1. Altın Kurallar ve Sürüm Yükseltme Stratejisi

* **Kural 1: Dikey Sıralama:** Her zaman önce Control Plane (Master) düğümleri güncellenmeli, Worker düğümleri ardından sırayla güncellenmelidir.
* **Kural 2: Sürüm Atlama Yasağı:** Minor sürümler arasında atlama yapılamaz (Örn: `v1.29`'dan `v1.31`'e doğrudan geçilemez. Önce `v1.29` ──► `v1.30`'a, ardından `v1.30` ──► `v1.31`'e yükseltilmelidir).
* **Kural 3: etcd Yedeği:** Yükseltme işlemine başlamadan hemen önce mutlaka çalışan sağlıklı bir etcd snapshot yedeği alınmalıdır.
* **Kural 4: Sıralı Tahliye (Drain):** Her worker düğümü güncellenmeden önce `cordon` ve `drain` edilerek üzerindeki podlar diğer sunuculara güvenle taşınmalıdır.
* **Kural 5: Test Ortamı:** Yükseltme işlemi canlı ortama uygulanmadan önce birebir kopyası olan bir test/staging kümesinde simüle edilmelidir.

---

## 2. Yükseltme Öncesi Kontroller (Pre-Upgrade Diagnostics)

```bash
# 1. Mevcut sürümleri kontrol edin
kubectl version --short
kubectl get nodes -o wide

# 2. Paket depolarındaki güncel sürümleri listeleyin
apt-cache madison kubeadm | head -n 10

# 3. API Deprecation (Kaldırılan API'ler) kontrolü
# (Pluto veya kubent gibi araçlar kullanılarak eski API kullanan manifestolar tespit edilir)
pluto detect-helm --target-versions k8s=v1.32

# 4. Yükseltme öncesi son bir etcd yedeği alın
export ETCDCTL_API=3
sudo etcdctl snapshot save /backup/pre-upgrade-etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## 3. Control Plane (Master) Yükseltme Adımları

Control plane düğümü üzerinde aşağıdaki adımları sırasıyla çalıştırın:

```bash
# 1. kubeadm paketinin kilidini kaldırın ve hedef sürüme güncelleyin
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.32.1-1.1
sudo apt-mark hold kubeadm

# 2. Yükseltme planını kontrol edin (Bileşen sürümleri ve API uyarıları listelenir)
sudo kubeadm upgrade plan v1.32.1

# 3. Yükseltme işlemini uygulayın (API Server, Controller Manager, Scheduler, CoreDNS güncellenir)
sudo kubeadm upgrade apply v1.32.1 --yes

# 4. Kubelet ve Kubectl paketlerini güncelleyip servisi yeniden başlatın
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.32.1-1.1 kubectl=1.32.1-1.1
sudo apt-mark hold kubelet kubectl

# Kubelet'i yeniden tetikleyin
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## 4. Worker Düğümlerinin Sırayla Yükseltilmesi (Sıralı Rollout)

Her worker düğümünü tek tek güncelleyin. Tüm düğümleri aynı anda güncellemek kesintiye yol açar.

```bash
# ADIM 1: Master düğümünden ilgili worker düğümünü planlamaya kapatın ve tahliye edin
kubectl cordon k8s-worker-01
kubectl drain k8s-worker-01 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=60

# ADIM 2: Worker düğümüne SSH ile bağlanın ve paketleri güncelleyin
ssh k8s-worker-01

sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.32.1-1.1
sudo apt-mark hold kubeadm

# Worker düğüm konfigürasyonunu güncelleyin
sudo kubeadm upgrade node

# Kubelet'i güncelleyin ve yeniden başlatın
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.32.1-1.1 kubectl=1.32.1-1.1
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet
exit # Master sunucuya geri dönün

# ADIM 3: Master düğümünden worker düğümünü tekrar aktif hale getirin
kubectl uncordon k8s-worker-01

# Düğüm durumunu doğrulayın
kubectl get nodes
```

---

## 5. Çoklu Master (HA) Control Plane Yükseltmesi

Yüksek kullanılabilirliğe sahip (HA) kümelerde master düğümlerinin etcd quorum dengesini korumak için sırayla yükseltilmesi gerekir:

* **Master Düğüm 1 (Primary):** `kubeadm upgrade apply v1.32.1` komutu çalıştırılır.
* **Master Düğüm 2 ve 3:** İlk master tamamlandıktan sonra, buralarda apply yerine **`kubeadm upgrade node`** komutu çalıştırılır.
* Ardından tüm master düğümlerinde `kubelet` paketleri güncellenip servisler yeniden başlatılır.

---

## 6. Yönetilen Bulut (Managed) Kubernetes Servislerinde Güncelleme

EKS, GKE ve AKS gibi yönetilen servislerde master düğüm yönetimi bulut sağlayıcıda olduğundan yükseltme işlemleri CLI araçlarıyla tetiklenir:

```bash
# AWS EKS Küme Sürüm Yükseltme
aws eks update-cluster-version --name my-cluster --kubernetes-version 1.32

# Google GKE Master Yükseltme
gcloud container clusters upgrade my-cluster --master --cluster-version 1.32

# Azure AKS Sürüm Yükseltme
az aks upgrade --resource-group myRG --name my-cluster --kubernetes-version 1.32.1 --yes
```

---

## 7. Yükseltme Sonrası Doğrulama ve Sağlık Kontrolleri

```bash
# 1. Tüm düğümlerin yeni sürüme geçtiğini kontrol edin
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,STATUS:.status.conditions[-1].type

# 2. Sistem podlarının sağlık durumunu sorgulayın
kubectl get pods -n kube-system

# 3. API Server sağlık uç noktalarına istek atın (200 OK dönmelidir)
kubectl get --raw /healthz
kubectl get --raw /readyz
```

---

## Özet

Kubernetes sürüm yükseltme işlemleri, her zaman **Master -> Worker** sıralamasına sadık kalınarak gerçekleştirilir. Yükseltme öncesinde kaldırılan API'lerin (**deprecated APIs**) kontrol edilmesi, **etcd** yedeklerinin alınması ve her düğümün sırayla **drain** edilerek güncellenmesi, sıfır kesintili (zero-downtime) bir altyapı geçişinin temel kurallarıdır.

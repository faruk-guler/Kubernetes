# CKA / CKAD / CKS Sertifikasyon Hazırlık Rehberi

Linux Foundation tarafından sunulan Kubernetes sertifikasyon sınavları (CKA, CKAD, CKS), çoktan seçmeli teorik sorular içermez. Tamamen terminal tabanlı, uygulamalı ve gerçek zamanlı Kubernetes kümeleri üzerinde senaryoların çözülmesine dayalı sınavlardır. Bu rehber, sınavların konu dağılımlarını, kritik terminal komutlarını ve hazırlık taktiklerini sunar.

---

## 1. Sınavlara Genel Bakış ve Kapsam

| Sertifika | Açılımı | Hedef Kitle | Süre | Baraj Puanı |
| :--- | :--- | :--- | :--- | :--- |
| **CKA** | Certified Kubernetes Administrator | Küme Yöneticileri, Sistem Mühendisleri | 2 Saat | %66 |
| **CKAD** | Certified Kubernetes Application Developer | Uygulama Geliştiricileri, DevOps Mühendisleri | 2 Saat | %66 |
| **CKS** | Certified Kubernetes Security Specialist | Güvenlik Mühendisleri (Önşart: Aktif CKA) | 2 Saat | %67 |

---

## 2. Sınav Konu Dağılımları

### CKA (Küme Yönetimi)

* **Küme Mimarisi, Kurulum ve Güncelleme (%25):** `kubeadm` ile küme kurulumu, versiyon yükseltme (upgrade) ve `etcd` yedekleme/kurtarma.
* **İş Yükleri ve Zamanlama (%15):** Deployments, DaemonSets, StatefulSets ve düğüm planlama (Affinity, Taints/Tolerations).
* **Servisler ve Ağ Yapısı (%20):** Service türleri, Ingress tanımları, NetworkPolicy ve CoreDNS.
* **Depolama Yönetimi (%10):** PV, PVC, StorageClass ve Volume erişim modları.
* **Sorun Giderme (%30):** Pod çöküşleri, düğüm arızaları ve kubelet log teşhisleri.

### CKAD (Uygulama Geliştirme)

* **Uygulama Tasarımı ve Derleme (%20):** Init Containers, Sidecar pod kalıpları ve Jobs/CronJobs.
* **Uygulama Dağıtımı (%20):** Güncelleme stratejileri (RollingUpdate), Helm grafik düzenlemeleri ve Kustomize.
* **Gözlemlenebilirlik ve Bakım (%15):** Sağlık kontrolleri (Probes), log analizi ve `kubectl debug`.
* **Yapılandırma ve Güvenlik (%25):** ConfigMap, Secret, ServiceAccount ve SecurityContext.

### CKS (Güvenlik Uzmanlığı)

* **Küme Kurulumu Güvenliği (%10):** CIS Benchmark analizi, NetworkPolicy ve API Server mTLS.
* **Küme Sıkılaştırma (%15):** RBAC denetimleri, ServiceAccount yetkilerinin kısıtlanması ve API erişim güvenliği.
* **Sistem Güvenliği (%15):** OS düzeyi kısıtlamalar, AppArmor ve Seccomp güvenlik profilleri.
* **Tedarik Zinciri Güvenliği (%20):** İmaj taraması (Trivy), imaj imzalama (Cosign) ve Admission Controllers.
* **Çalışma Zamanı Güvenliği (%20):** Falco ile konteyner hareket analizi ve API Server Audit Log takibi.

---

## 3. Zaman Kazandıran Terminal Kısayolları ve Taktikler

Sınavda zamanı verimli kullanabilmek için terminalde şu alias ve ayarları mutlaka yapın:

```bash
# 1. kubectl Kısayolu ve Auto-Completion Aktifleştirme
alias k=kubectl
complete -o default -F __start_kubectl k

# 2. Hızlı YAML Üretimi İçin Değişken Tanımlama
export do="--dry-run=client -o yaml"

# Örnek Kullanım:
k create deploy web-deployment --image=nginx:1.26 $do > deploy.yaml
# (deploy.yaml dosyasını açıp düzenleyin ve uygulayın)
```

### Hızlı Yardım (`explain`)

Herhangi bir kaynağın YAML şemasını unuttuysanız dokümantasyonda aramak yerine terminalden explain komutunu kullanın:

```bash
# Bir pod içindeki resources yapısının alt alanlarını listeleme
kubectl explain pod.spec.containers.resources
```

---

## 4. Kritik Sınav Görevleri ve Kod Şablonları

### A. etcd Snapshot Kaydetme ve Geri Yükleme (CKA)

```bash
# Yedek alma komutu
ETCDCTL_API=3 etcdctl snapshot save /var/lib/backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

### B. kubeadm ile Control Plane Sürüm Yükseltme (CKA)

```bash
# 1. Paket depolarını güncelleyin ve kubeadm'i kurun
apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.30.0-1.1
apt-mark hold kubeadm

# 2. Upgrade planını kontrol edin ve uygulayın
kubeadm upgrade plan
kubeadm upgrade apply v1.30.0

# 3. Kubelet ve kubectl paketlerini güncelleyip servisi yeniden başlatın
apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.30.0-1.1 kubectl=1.30.0-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
```

### C. NetworkPolicy Tanımlama (CKS/CKA)

Sadece `app: backend` etiketine sahip podlardan 80 portuna gelen trafiğe izin veren NetworkPolicy:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cka_ckad_cks_sertifikasyon_rehberi_manifest_1.yaml](../Manifests/14_migration/cka_ckad_cks_sertifikasyon_rehberi_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### D. Sidecar Container Tanımı (CKAD)

Ana konteynerin logunu okuyup ekrana yazan yan (sidecar) konteyner pod örneği:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cka_ckad_cks_sertifikasyon_rehberi_manifest_2.yaml](../Manifests/14_migration/cka_ckad_cks_sertifikasyon_rehberi_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Önerilen Hazırlık Taktikleri

1. **Resmi Sınav Simülatörü (killer.sh):** Sınav kaydı sonrasında ücretsiz verilen 2 adet killer.sh simülasyon hakkını mutlaka kullanın. killer.sh, gerçek sınav sorularına göre %50 daha zordur. Simülatörde 70+ puan alabiliyorsanız gerçek sınavı rahatlıkla geçersiniz.
2. **Bookmarks (Sınavda İzin Verilen Kaynaklar):** Sınav sırasında sadece resmi Kubernetes dokümantasyon sayfasına (`kubernetes.io/docs`) erişim serbesttir. Tarayıcınıza etcd backup, kubeadm upgrade, ingress ve networkpolicy gibi sık kullanılan sayfaların linklerini şimdiden yer imi (bookmark) olarak ekleyin.

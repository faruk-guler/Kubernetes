# CIS Kubernetes Güvenlik Standardı (CIS Benchmark)

**Center for Internet Security (CIS) Kubernetes Benchmark**, Kubernetes kümelerinin (control plane, worker node'lar, etcd ve network politikaları) siber güvenlik yapılandırmalarını denetlemek ve sıkılaştırmak için dünya genelinde kabul görmüş en prestijli referans standarttır. Bağımsız denetçiler, PCI-DSS, SOC2 ve ISO 27001 gibi uyumluluk raporlarında bu standarda uyumu şart koşarlar.

---

## 1. Benchmark Kategorileri ve Kontrolleri

CIS Kubernetes Benchmark (2026 yılı itibarıyla güncel v1.8+ standartlarında) 4 ana bölüme ayrılır:

### A. Control Plane Bileşenleri (Master Nodes)

API sunucusu, scheduler, controller manager ve etcd yapılandırma dosyalarının ve çalışan parametrelerinin güvenliğini kapsar.

* **Kritik Kontroller:**
  * `1.2.1` `--anonymous-auth=false` (Anonim kullanıcı erişimlerini kapat).
  * `1.2.7` `--authorization-mode=Node,RBAC` (RBAC yetkilendirmesini zorunlu kıl).
  * `1.2.22` `--audit-log-path` (Denetim günlüklerini aktif et).
  * `1.2.31` `--tls-min-version=VersionTLS12` (TLS 1.2 veya 1.3 zorunlu kıl).
  * `1.2.34` `--encryption-provider-config` (Verilerin diskte şifrelenmesini sağla).

### B. etcd Güvenliği

Kubernetes veritabanı olan etcd'nin yetkisiz erişimlere karşı kilitlenmesini hedefler.

* **Kritik Kontroller:**
  * `2.1` etcd'nin tüm trafiği TLS sertifikaları ile şifrelenmelidir.
  * `2.2` `--client-cert-auth=true` ile sadece sertifikası olan API sunucuları veritabanı ile konuşabilmelidir.

### C. Worker Node ve Kubelet Güvenliği

İşçi düğümlerinde koşan kubelet ajanının ve işletim sisteminin güvenliğini denetler.

* **Kritik Kontroller:**
  * `4.2.1` Kubelet anonim isteklerini kapat (`--anonymous-auth=false`).
  * `4.2.2` Kubelet yetkilendirmesini Webhook moduna al (`--authorization-mode=Webhook`).
  * `4.2.6` Salt okunur kubelet portunu (10255) kesinlikle kapat.
  * `4.2.10` İstemci sertifikalarını otomatik yenile (`--rotate-certificates=true`).

---

## 2. kube-bench ile Otomatik CIS Taraması

**kube-bench**, Aqua Security tarafından geliştirilen ve kümenizin CIS standartlarına uyumluluğunu saniyeler içinde otomatik olarak tarayan açık kaynaklı bir araçtır.

### Kubernetes Job Olarak Çalıştırma

kube-bench'i kümenizde bir Kubernetes Job olarak başlatıp sonuçları okumak için:

```bash
# 1. Küme üzerinde kube-bench job'u oluşturun
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# 2. Job'un tamamlanmasını bekleyin
kubectl wait --for=condition=complete job/kube-bench --timeout=60s

# 3. Tarama raporu çıktılarını okuyun
kubectl logs job/kube-bench
```

### Örnek kube-bench Sonucu ve Yorumlanması

```text
[PASS] 1.1.1 API server pod spec dosya izinleri 600 veya 644 olarak ayarlanmış
[FAIL] 1.2.1 --anonymous-auth parametresi false olarak ayarlanmamış! (Düzeltilmeli!)
[WARN] 1.2.16 Audit log boyut sınırı (maxsize) ayarlanmamış
[INFO] 1.2.17 Audit log yedekleme sayısı (maxbackup): varsayılan
```

* `[PASS]`: Kurala uyulmuş (Güvenli).
* `[FAIL]`: Kritik bir güvenlik açığı var, parametrenin acilen düzeltilmesi gerekir.
* `[WARN]`: Düşük öncelikli tavsiye. Kurumsal ihtiyacınıza göre değerlendirebilirsiniz.

### Sunucu Üzerinde Doğrudan Çalıştırma (Binary)

Eğer Master/Worker node'ların işletim sistemlerine doğrudan erişiminiz varsa:

```bash
# Sadece Master/Control Plane bileşenlerini tara
./kube-bench run --targets master

# Sadece Worker Node/Kubelet durumunu tara
./kube-bench run --targets node
```

---

## 3. Trivy CLI ile Hızlı Yapılandırma Taraması

Trivy, imaj taramanın yanı sıra Kubernetes kümenizin CIS Benchmark uyumluluk durumunu da komut satırından hızlıca denetleyebilir:

```bash
# 1. Küme geneli uyumluluk özet raporu alma
trivy k8s --report summary cluster

# 2. Sadece belirli bir namespace (Örn: production) için CIS raporu alma
trivy k8s --report summary -n production

# 3. Tüm hatalı yapılandırmaları detaylı listeleme
trivy k8s --report all --misconfig cluster
```

---

## 4. Kritik `kube-apiserver` Güvenlik Parametreleri

kube-apiserver manifest dosyasında (`/etc/kubernetes/manifests/kube-apiserver.yaml`) bulunması gereken ve CIS Benchmark'tan geçmenizi sağlayan ideal parametre listesi:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cis_benchmark_manifest_1.yaml](../Manifests/07_security/cis_benchmark_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### etcd At-Rest Encryption (encryption-config.yaml) Örneği

Kubernetes üzerindeki secret nesnelerinin veritabanına düz metin (plain text) yerine AES-GCM algoritmasıyla şifrelenerek yazılması için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cis_benchmark_manifest_2.yaml](../Manifests/07_security/cis_benchmark_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Hızlı CIS Uyumluluk Kontrol Listesi

* [ ] `kube-bench` çalıştırıldı ve hiçbir `[FAIL]` kalmadı.
* [ ] API Server anonim erişimleri kapatıldı (`--anonymous-auth=false`).
* [ ] etcd verileri diskte şifrelendi (EncryptionConfiguration kuruldu).
* [ ] API Server Audit Log politikaları aktif edildi ve loglar harici bir diske taşındı.
* [ ] Kubelet read-only portu (`10255`) kapatıldı.
* [ ] TLS minimum sürümü `VersionTLS12` veya üzeri olarak kısıtlandı.
* [ ] Control plane dosya izinleri (`/etc/kubernetes/manifests/`) `600` veya `644` olarak ayarlandı.

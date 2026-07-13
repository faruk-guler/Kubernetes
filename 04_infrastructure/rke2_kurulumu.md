# RKE2 ile Güvenlik Odaklı Kurulum (RKE2 Installation)

**RKE2 (Rancher Kubernetes Engine 2)**, kurumsal dünyada finans, bankacılık, savunma sanayii ve kamu sektörü gibi güvenliğin en üst düzeyde öncelikli olduğu alanlar için tasarlanmış, öntanımlı olarak sıkılaştırılmış (**hardened**) bir Kubernetes dağıtımıdır.

RKE2, Federal Bilgi İşleme Standartları (FIPS 140-2) uyumluluğu, otomatik CIS Benchmark kontrolleri ve kolay hava boşluklu (air-gapped) kurulum özellikleri ile öne çıkar.

---

## 1. Neden RKE2?

| Özellik | kubeadm | RKE2 |
|:---|:---:|:---:|
| **FIPS 140-2 Kriptografi Uyumu** | ❌ Hayır | ✅ Evet |
| **CIS Benchmark Standartları** | Manuel yapılandırılır | Otomatik yapılandırılmış gelir |
| **STIG Güvenlik Standartları** | ❌ Hayır | ✅ Evet |
| **İnternetsiz (Air-gap) Kurulum** | Zor ve karmaşık | Son derece kolay (bundled artifacts) |
| **Ağ Bileşenleri (CNI)** | Manuel kurulur | Öntanımlı olarak hazır gelir (Canal/Cilium) |
| **İşletim Sistemi Desteği** | Kısmi | Tam (SELinux ve AppArmor entegrasyonu dahil) |

---

## 2. Minimum Sistem Gereksinimleri

RKE2'nin kurumsal standartlarda çalışabilmesi için düğümlerde (nodes) aşağıdaki minimum kaynakların bulunması önerilir:

* **Server (Master) Düğümü:** 4 vCPU, 8 GB RAM, 100 GB Disk
* **Agent (Worker) Düğümü:** 4 vCPU, 8 GB RAM, 100 GB Disk
* *Önemli: Sunucu hostname'lerinin benzersiz olması ve `/etc/hosts` üzerinde tanımlanması şarttır.*

---

## 3. Server (Master) Kurulum Adımları

RKE2, kurulum süreçlerini otomatize eden resmi bir script sunar.

### Adım 1: RKE2 Server Servisinin Yüklenmesi

```bash
# Kurulum script'ini çalıştırın (Otomatik olarak en kararlı sürümü kurar)
curl -sfL https://get.rke2.io | sh -
```

### Adım 2: Güvenlik Yapılandırmasının Oluşturulması

Kurulum sonrasında RKE2'nin davranışını belirlemek için `/etc/rancher/rke2/config.yaml` yapılandırma dosyası oluşturulmalıdır:

```yaml
# /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"
profile: "cis" # CIS Kubernetes Benchmark uyumluluğunu otomatik aktif eder
token: "KurumsalGuvenliTokenDegeri123" # Worker'ların bağlanırken kullanacağı token
cni: "cilium" # Varsayılan CNI olarak Cilium kullan
```

### Adım 3: Servisin Başlatılması

```bash
# Servisi sistem başlangıcına ekleyin ve çalıştırın
systemctl enable rke2-server.service
systemctl start rke2-server.service

# Kurulum durumunu loglardan takip edin
journalctl -u rke2-server -f
```

### Adım 4: Kubeconfig ve kubectl Yapılandırması

RKE2 kendi bünyesinde kubectl aracıyla birlikte gelir. Mevcut kabuğunuzda aktif etmek için:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
# RKE2'nin kendi kubectl binary'sini sistem yoluna bağlama
ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl

# Test edin
kubectl get nodes
```

---

## 4. Agent (Worker) Düğümü Ekleme

Bir worker düğümünü RKE2 Server'a bağlamak için şu adımlar izlenir:

```bash
# 1. Hedef Worker makinede kurulumu agent tipiyle başlatın
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -

# 2. Yapılandırma dizinini oluşturun
mkdir -p /etc/rancher/rke2/

# 3. Server bağlantı detaylarını config dosyasına yazın
cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://<MASTER_IP_ADRESI>:9345
token: KurumsalGuvenliTokenDegeri123
EOF

# 4. Agent servisini çalıştırın
systemctl enable rke2-agent.service
systemctl start rke2-agent.service
```

---

## 5. Air-Gap (İnternetsiz/Hava Boşluklu) Kurulum

Tamamen izole ve dış dünyaya kapalı güvenli veri merkezlerinde kurulum yapabilmek için gerekli tüm imajlar ve binary'ler interneti olan bir bilgisayarda indirilip hedef sunucuya taşınır:

```bash
# 1. Paketleri interneti olan bilgisayarda indirin
curl -OL https://github.com/rancher/rke2/releases/download/v1.32.0+rke2r1/rke2-images.linux-amd64.tar.zst
curl -OL https://github.com/rancher/rke2/releases/download/v1.32.0+rke2r1/rke2.linux-amd64.tar.gz

# 2. Dosyaları hedef sunucuya kopyalayın ve gerekli dizine yerleştirin
mkdir -p /var/lib/rancher/rke2/agent/images/
cp rke2-images.linux-amd64.tar.zst /var/lib/rancher/rke2/agent/images/

# 3. Kurulumu yerel paketleri işaret ederek başlatın
INSTALL_RKE2_ARTIFACT_PATH=/path/to/downloads sh install.sh
```

---

## 6. CIS Benchmark Doğrulaması: `kube-bench`

Kümenin CIS güvenlik standartlarına ne kadar uyduğunu doğrulamak için Aqua Security'nin **kube-bench** aracı RKE2 profiliyle bir Job olarak çalıştırılabilir:

```bash
# RKE2 uyumlu kube-bench job'unu uygulayın
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-rke2.yaml

# Tarama sonuçlarını loglardan okuyun
kubectl logs job.batch/kube-bench
```

---

## 7. RKE2 Port ve Güvenlik Duvarı Gereksinimleri

Düğümler arasında iletişim için güvenlik duvarında (firewall) şu portların açılması zorunludur:

* **Control Plane (Server) Düğümü:**
  * **TCP 6443:** Kubernetes API Server erişimi
  * **TCP 9345:** RKE2 Supervisor portu (Node katılımı ve kimlik doğrulama için)
  * **TCP 2379-2380:** etcd veritabanı iletişimi
  * **TCP 10250:** Kubelet API
  * **UDP 8472:** VXLAN (Kapsülleme ağ trafiği)
* **Worker (Agent) Düğümü:**
  * **TCP 10250:** Kubelet API
  * **TCP 30000-32767:** NodePort servisleri
  * **UDP 8472:** VXLAN trafiği

---

## 8. Sertifika Rotasyonu ve Yönetimi

RKE2 sertifikaları otomatik olarak yıllık yenilenir. Ancak manuel olarak sertifikaları sıfırlamak veya yenilemek isterseniz:

```bash
# Sertifikaları manuel yenileyin
sudo rke2 certificate rotate

# Değişikliklerin yansıması için servisleri sırayla yeniden başlatın
sudo systemctl restart rke2-server  # Master sunucularda
sudo systemctl restart rke2-agent   # Worker sunucularda
```

---

## 9. RKE2 Sürüm Yükseltme (Upgrade)

RKE2 kümesini güvenli bir şekilde bir üst sürüme taşımak için:

1. **Node'u Tahliye Edin (Drain):**

   ```bash
   kubectl drain worker-node-1 --ignore-daemonsets --delete-emptydir-data
   ```

2. **Binary Güncellemesi:** Scripti en güncel kanalı işaret ederek çalıştırın:

   ```bash
   curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=latest sh -
   ```

3. **Servisi Yeniden Başlatın:** `systemctl restart rke2-server` veya `rke2-agent` servisini çalıştırın.
4. **Node'u Tekrar Aktif Edin (Uncordon):**

   ```bash
   kubectl uncordon worker-node-1
   ```

---

## Özet

RKE2, kurumsal ve regülasyona tabi endüstrilerde Kubernetes altyapısı kurmak için ideal seçimdir. Öntanımlı gelen sıkılaştırılmış güvenlik profilleri (**CIS profile**), kolaylaştırılmış hava boşluklu (**Air-gap**) kurulum süreçleri ve entegre paket yapısıyla, operasyonel ekiplerin güvenlik risklerini en aza indirir.

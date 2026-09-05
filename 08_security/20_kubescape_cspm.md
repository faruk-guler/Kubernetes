# Kubescape ile Küme Güvenlik Duruşu Yönetimi (CSPM)

Kubernetes ortamlarında güvenlik, sadece tek bir araçla çözülebilen bir problem değildir. İmaj taraması için Trivy, pod güvenliği için PSA, admission kontrolü için Kyverno kullandınız.
Peki **"Şu anda tüm kümem genelindeki güvenlik risklerim nelerdir, hangi NSA veya MITRE ATT&CK kurallarını ihlal ediyorum ve bunları nasıl düzeltirim?"** sorusunun cevabını kim verecek?

İşte bu noktada **CSPM (Cloud Security Posture Management - Bulut Güvenlik Duruşu Yönetimi)** araçları devreye girer. Bu alanın en popüler ve açık kaynaklı çözümü **Kubescape**'tir.

---

## 1. Kubescape Nedir?

**Kubescape**, ARMO tarafından geliştirilen ve CNCF'e (Cloud Native Computing Foundation) bağışlanan bir açık kaynaklı Kubernetes güvenlik aracıdır.

Kubescape şu işlemleri yapar:

1. Kümeyi NSA-CISA, MITRE ATT&CK ve CIS Benchmark standartlarına göre tarar.
2. YAML konfigürasyonlarındaki (Deployment, Service vb.) yapılandırma hatalarını (misconfigurations) bulur.
3. Çalışan kümedeki (Runtime) Role-Based Access Control (RBAC) yetkilerini analiz ederek gereksiz yüksek yetkileri tespit eder.
4. Tüm bu zafiyetlerin **nasıl çözüleceğini (remediation)** detaylıca açıklar.

---

## 2. Kubescape Kurulumu ve Kullanımı

### A. CLI (Komut Satırı) Olarak Kurulum

Kubescape'i doğrudan bilgisayarınıza (veya CI/CD sunucunuza) kurarak dışarıdan kümenizi tarayabilirsiniz.

```bash
# Linux / macOS
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash

# Windows (Powershell)
iwr -useb https://raw.githubusercontent.com/kubescape/kubescape/master/install.ps1 | iex
```

### B. İlk Tarama (Scan)

Kümenizi varsayılan (NSA) framework'üne göre anında taramak için:

```bash
kubescape scan
```

Belirli bir framework'e (Örn: MITRE) göre tarama yapmak için:

```bash
kubescape scan framework mitre
```

*Not: Çıktı çok uzun olabileceğinden, genellikle PDF, HTML veya JSON formatında çıktı alınması tercih edilir.*

```bash
kubescape scan --format html --output report.html
```

---

## 3. CI/CD Entegrasyonu

Kubescape, sadece canlı kümeyi değil, Git deponuzdaki (Repository) YAML veya Helm Chart dosyalarını da kümeye **gitmeden önce** tarayabilir. Bu sayede "Shift-Left" (Güvenliği sola, yani geliştirme aşamasına kaydırma) prensibi uygulanır.

```bash
# Sadece yerel dizindeki YAML dosyalarını tarama
kubescape scan ./manifests/*.yaml
```

Bir GitHub Actions iş akışında (workflow), eğer YAML dosyasında güvenlik açığı varsa derleme (build) işlemini iptal ettirebilirsiniz.

---

## 4. Kubescape Operator (Sürekli Gözlem)

CLI aracı anlık tarama yapar. Kümenizin sürekli ve 7/24 taranması için Kubescape'i bir Operator olarak kümenin içine kurmalısınız.

```bash
helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update
helm upgrade --install kubescape kubescape/kubescape-operator -n kubescape --create-namespace
```

Operator kurulduktan sonra, bulduğu sonuçları ücretsiz olarak **ARMO Cloud** paneline gönderebilir veya küme içinde bir Prometheus/Grafana paneline yansıtabilirsiniz.

---

## 5. Kubescape vs. Trivy Operator

Hem Trivy Operator hem de Kubescape benzer işler yapıyor gibi görünebilir. SRE pratiklerinde genellikle ikisinin kombinasyonu kullanılır:

* **Trivy Operator:** Temelde **imaj zafiyetlerine (CVE - Vulnerabilities)** odaklanır. Konteynerin içindeki işletim sistemi açıklarını ve kütüphane zafiyetlerini (Örn: Log4j) en iyi Trivy bulur.
* **Kubescape:** Temelde **Kubernetes duruşuna ve yapılandırmalarına (Posture / Misconfiguration)** odaklanır. NSA rehberine uyumluluk, RBAC analizi (Gereksiz cluster-admin yetkileri) ve MITRE tehdit vektörlerini en iyi Kubescape bulur.

## Özet

Kümenizi ne kadar iyi yapılandırırsanız yapılandırın, gözden kaçan bir `privileged: true` veya `hostNetwork: true` ayarı tüm sistemi riske atabilir. **Kubescape**, sistem yöneticisine bir denetçi (auditor) gözüyle "İşte kümenin eksik listesi ve düzeltme yolları" diyen en değerli asistanlardan biridir.

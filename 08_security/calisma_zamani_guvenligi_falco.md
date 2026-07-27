# Çalışma Zamanı (Runtime) Güvenliği: Falco ve Trivy Operator

Kubernetes kümenizde konteyner imajlarını statik olarak taradınız, RBAC yetkilerini sınırladınız ve Pod Security Standards (PSS) kurallarını aktif ettiniz. Peki ya çalışan bir konteynerin içine sızan bir saldırgan aniden `/etc/shadow` dosyasını okumaya çalışırsa, ya da container içinde yeni bir shell (komut satırı) başlatıp dış dünyaya bağlantı kurarsa ne olur?

İşte bu tür anlık ve beklenmeyen siber güvenlik olaylarını yakalamak için **Çalışma Zamanı Güvenliği (Runtime Security)** katmanı devreye girer.

---

## 1. Güvenlik Katmanları ve Çalışma Zamanları

Kubernetes güvenlik yaşam döngüsü üç temel aşamaya ayrılır:

| Güvenlik Katmanı | Ne Zaman Devreye Girer? | Temel Amacı | Kullanılan Araçlar |
| :--- | :---: | :--- | :--- |
| **Statik Güvenlik** | Build (Derleme) Aşaması | İmaj içi zafiyetler ve hatalı YAML taraması | Trivy, Snyk, Checkov |
| **Kabul Denetimi (Admission)** | Deploy (Dağıtım) Aşaması | Küme standartlarına uymayan kaynakların engellenmesi | Kyverno, OPA, CEL |
| **Çalışma Zamanı (Runtime)** | Run (Çalışma) Aşaması | Canlı konteynerde şüpheli aktivite izleme | **Falco**, Tetragon, NeuVector |

---

## 2. NeuVector (Tam Yaşam Döngüsü Güvenliği)

**NeuVector** (Suse tarafından açık kaynak haline getirilen CNCF projesi), çalışan podlar arasındaki L7 ağ trafiğini canlı analiz eden, şüpheli paketleri engelleyen (WAF/DPI) ve otomatik zero-trust ağ kuralları üreten uçtan uca bir güvenlik platformudur.

```bash
# Helm ile NeuVector kurulumu
helm repo add neuvector https://neuvector.github.io/neuvector-helm/
helm repo update
helm install neuvector neuvector/core --namespace neuvector --create-namespace
```

---

## 3. Falco ile Çalışma Zamanı Tehdit Algılama

Çalışma zamanı güvenliğinin fiili endüstri standardı **Falco**'dur. Falco, Linux çekirdeğinden (Kernel) gelen sistem çağrılarını (**eBPF** sürücüsü aracılığıyla) dinler. Önceden tanımlanmış kurallara uymayan şüpheli bir işlem algılandığında (örneğin dosya sahipliği değişimi, yetkisiz port açılması vb.) anlık uyarı üretir.

```bash
# Helm ile eBPF sürücüsünü kullanarak Falco kurulumu:
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set falcosidekick.enabled=true
```

---

## 4. Falco Kuralları (Rules) Yapılandırması

Falco kuralları, sistem çağrılarını (syscalls) izleyen mantıksal ifadelerdir. Aşağıdaki örnekte, bir konteyner içinde shell (bash/sh) çalıştırıldığında tetiklenecek özel bir kural tanımlanmıştır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [calisma_zamani_guvenligi_falco_manifest_1.yaml](../Manifests/07_security/calisma_zamani_guvenligi_falco_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu kural sayesinde, bir saldırgan `kubectl exec` veya başka bir açık vasıtasıyla pod içine sızıp terminal başlattığında Falco bunu anında yakalar.

---

## 5. FalcoSidekick: Bildirimleri Yönlendirme

Falco'nun ürettiği uyarıları anlık olarak Slack, Microsoft Teams, Elasticsearch, PagerDuty veya Discord gibi kanallara iletmek için **Falcosidekick** bileşeni kullanılır.

```yaml
# Helm upgrade komutu ile Slack entegrasyonunu aktif etme:
helm upgrade falco falcosecurity/falco -n falco \
  --set falcosidekick.enabled=true \
  --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/services/T00/B00/XX" \
  --set falcosidekick.config.slack.minimumpriority="warning"
```

---

## 6. Trivy Operator ile Sürekli Güvenlik Taraması

Güvenlik taramalarını sadece CI/CD aşamasında yapmak 2026 yılı standartlarında yeterli kabul edilmemektedir. Kümede aylar önce deploy edilmiş bir podun imajında bugün yeni bir güvenlik açığı (Zero-Day zafiyeti) keşfedilebilir.

**Trivy Operator**, kümede çalışan tüm podları ve imajları arka planda sürekli tarar ve sonuçları Kubernetes CRD nesneleri (`VulnerabilityReport`, `ConfigAuditReport`) olarak küme veritabanına kaydeder.

```bash
# 1. Trivy Operator Kurulumu
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set trivy.ignoreUnfixed=true # Cozumu (yaması) olmayan aciklari rapora ekleme

# 2. Küme genelinde anlık güvenlik durum ozeti
trivy k8s --report summary cluster

# 3. Sadece production namespace'ini tarama
trivy k8s --report summary -n production
```

### Güvenlik Raporlarını Okuma (Kubectl)

Trivy Operator'ın ürettiği raporları standart `kubectl` komutlarıyla sorgulayabilirsiniz:

```bash
# 1. Kümedeki tüm imaj zafiyeti (vulnerability) raporlarını listeleyin
kubectl get vulnerabilityreports -A

# 2. Hatalı YAML yapılandırmalarını (Örn: privileged: true olanlar) listeleyin
kubectl get configauditreports -A

# 3. Belirli bir podun detaylı güvenlik açığı raporunu inceleyin
kubectl describe vulnerabilityreport  db-pod-mysql -n production
```

---

## 7. Özet

**Falco** ve **Trivy Operator** birlikte kullanıldığında tam koruma sağlar:

* **Trivy Operator**, kümedeki imajların zafiyetlerini ve statik yapılandırma açıklarını sürekli denetler (Pasif Koruma).
* **Falco**, canlı ortamda sızma girişimi veya şüpheli çekirdek çağrılarını anlık yakalayıp uyarır (Aktif Koruma).

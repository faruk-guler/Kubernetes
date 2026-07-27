# Kubecost ile Kubernetes Maliyet Yönetimi ve Raporlama

Kubernetes üzerinde koşan uygulamaların bulut (AWS, GCP, Azure) faturalarını şeffaf bir şekilde analiz etmek, hangi ekibin veya hangi mikroservisin ne kadar harcama yaptığını para birimi (TL/USD) bazında görmek kurumsal FinOps süreçlerinin en kritik adımıdır. **Kubecost**, Kubernetes API'sini ve fatura verilerini birleştirerek gerçek zamanlı maliyet takibi ve bütçe yönetimi sağlayan açık kaynaklı bir araçtır.

---

## 1. Kubecost Kurulumu ve Arayüze Erişim

Mevcut Prometheus altyapınızla entegre şekilde Kubecost'u kurmak için:

```bash
# 1. Kubecost Deposunu Ekleyin
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/
helm repo update

# 2. Mevcut Prometheus ile Entegre Kurulum (Prometheus'u yeniden kurmamak için)
helm install kubecost cost-analyzer/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set global.prometheus.enabled=false \
  --set global.prometheus.fqdn=http://prometheus-operated.monitoring.svc.cluster.local:9090

# 3. Kubecost Web Arayüzünü Yönlendirin
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
# Tarayıcıdan http://localhost:9090 adresine gidin
```

---

## 2. Temel Kavramlar: Rezerve Edilen (Request) vs. Gerçek Kullanım (Usage)

Kubecost, maliyet optimizasyonunda iki kavram arasındaki farkı temel alır:

* **Request Cost (Talep Maliyeti):** Pod'un deployment dosyasında talep ettiği (rezerve edilen) CPU/RAM miktarına göre bulut sağlayıcısına ödenen sabit bedel. Pod hiç çalışmasa dahi bu kaynak rezerve edildiği için para ödenir.
* **Usage Cost (Kullanım Maliyeti):** Pod'un işlem yaparken aktif olarak tükettiği gerçek kaynakların maliyeti.

Eğer rezerve edilen kaynak (Request), gerçek kullanımın (Usage) çok üzerindeyse, sisteminizde kaynak israfı (**Efficiency/Verimlilik** skorunun düşmesi) var demektir. Kubecost bu farka bakarak otomatik olarak "Right-sizing" (yeniden boyutlandırma) önerileri sunar.

### Kubecost CLI (`kubectl-cost`) ile Maliyet Raporları Alma

Kubecost komut satırı aracıyla doğrudan terminal üzerinden maliyetleri listeleyebilirsiniz:

```bash
# 1. Son 2 saatteki isim alanlarının (namespaces) maliyet dağılımını göster:
kubectl cost namespace --show-all-resources 2h

# 2. production namespace'indeki tüm deployment'ların CPU ve Bellek harcamalarını süzün:
kubectl cost deployment --show-cpu --show-memory -n production
```

---

## 3. Kubecost Maliyet Alarmları (Maliyet Sınırı - Budget Alerting)

Maliyetlerde sıradışı bir artış (anomaly) olduğunda veya belirlenen aylık bütçe aşıldığında Slack üzerinden anlık bildirim almak için Kubecost alert politikaları tanımlanabilir:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kubecost_manifest_1.yaml](../Manifests/10_platform/kubecost_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Kubecost ile Maliyet Tasarrufu Stratejileri

Kubecost arayüzündeki **Savings** sekmesi, kümenizde uygulayabileceğiniz tasarruf adımlarını potansiyel kazanç oranlarıyla listeler:

### A. Right-sizing (Yeniden Boyutlandırma)

Kubecost, podların gerçek CPU ve RAM kullanım geçmişini izleyerek en verimli sınırları hesaplar.

```bash
# Gereksiz yüksek kaynak talep eden ve küçültülebilecek pod listesini çekin:
kubectl cost savings --show-recommendations -n production
```

### B. Spot Instance Potansiyel Tasarrufu

Kubecost, kümedeki hangi uygulamaların (Örn: Stateful olmayan, toleransı yüksek mikroservisler) Spot sunuculara taşınabileceğini analiz eder ve bu geçiş yapıldığında aylık ne kadar tasarruf edileceğini hesaplar (Örn: "%75 Spot geçiş tasarrufu").

### C. Cluster Autoscaler / Düğüm Konsolidasyonu (Node Consolidation)

Kümede çok az pod barındıran atıl durumdaki büyük sunucuların kapatılması ve podların diğer sunucularda birleştirilmesi (consolidation) önerilerini sunar. Karpenter entegrasyonu ile bu birleştirme otonom olarak yapılır.

### D. Namespace Kaynak Kotalarının Belirlenmesi

Ekiplerin kontrolsüzce büyük kaynaklar tüketmesini engellemek için isim alanlarına `ResourceQuota` kuralı uygulanması israfı kökten engeller.
*(Detaylı kota şablonları için bkz: [finops_ve_maliyet_optimizasyonu.md](finops_ve_maliyet_optimizasyonu.md))*

---

## 5. Grafana Entegrasyonu

Kubecost, topladığı maliyet metriklerini (`kubecost_cluster_memory_working_set_bytes`, `node_total_hourly_cost` vb.) Prometheus'a yazar. Bu metrikleri kendi Grafana panellerinize eklemek için **15757** numaralı resmi Kubecost Grafana Dashboard ID'sini içe aktararak kullanabilirsiniz.

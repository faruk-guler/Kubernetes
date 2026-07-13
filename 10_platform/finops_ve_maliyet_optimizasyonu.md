# FinOps ve Kubernetes Maliyet Optimizasyonu (FinOps Guide)

Kubernetes üzerinde kaynak yönetimi çok kolay bir şekilde israfa dönüşebilir. Hatalı ayarlanmış CPU/RAM limitleri, boşta çalışan atıl düğümler (nodes), kullanılmayan persistente volume'lar (PVC) ve unutulmuş test isim alanları (namespaces) her ay bütçenizi sessizce tüketir. **FinOps**, bulut maliyetlerini görünür kılan, ekipler arasında sorumluluk paylaşımını artıran ve kaynak kullanımını otomatik olarak optimize eden finansal operasyon disiplinidir.

---

## 1. Maliyet Görünürlüğü ve Kubecost Kurulumu

Kubernetes kaynak harcamalarını kuruşu kuruşuna, namespace ve pod bazlı raporlamak için en popüler araç **Kubecost**'tur.

```bash
# 1. Kubecost Helm Deposunu Ekleyin ve Kurun
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/
helm repo update

helm install kubecost cost-analyzer/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="sample-token-2026" \
  --set prometheus.server.persistentVolume.storageClass=longhorn

# 2. Arayüze erişim sağlamak için yönlendirme başlatın
kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090
# Tarayıcıdan http://localhost:9090 adresine gidin
```

---

## 2. Kaynak İsrafı Tespiti ve Raporlama

### A. Aşırı Kaynak Verilen (Over-provisioned) Podların Bulunması (PromQL)

Bir pod'un talep ettiği (request) CPU miktarı ile gerçekte harcadığı ortalama CPU arasındaki farkı (israfı) bulup listeleyen sorgu:

```promql
# 0.5 core (500m CPU)'dan fazla israf yapan podlar:
(
  sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace, pod)
  -
  sum(rate(container_cpu_usage_seconds_total{container!=""}[1h])) by (namespace, pod)
) > 0.5
```

### B. Sahipsiz ve Atıl Disklerin (Unused PVCs) Tespiti

Bir pod'a bağlı olmayan ve boşta durduğu için boşuna para ödenen disklerin taranması:

```bash
# Durumu Bound (Bağlı) olan fakat hiçbir pod tarafından aktif kullanılmayan PVC'leri bulun:
kubectl get pvc -A -o json | jq '.items[] | select(.status.phase=="Bound") |
  select(.metadata.annotations["volume.kubernetes.io/selected-node"] == null) |
  {name: .metadata.name, namespace: .metadata.namespace, size: .spec.resources.requests.storage}'
```

---

## 3. Maliyet Optimizasyon Stratejileri

### Strateji 1: VPA (Vertical Pod Autoscaler) ile Right-Sizing

VPA, uygulamaların geçmiş kullanım verilerini inceleyerek CPU ve Bellek taleplerini (requests/limits) en ideal boyutlara çekmenizi sağlar.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [finops_ve_maliyet_optimizasyonu_manifest_1.yaml](../Manifests/10_platform/finops_ve_maliyet_optimizasyonu_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Önerileri izlemek için:
`kubectl describe vpa payment-api-vpa -n production`

---

### Strateji 2: Spot / Preemptible Node Kullanımı

Bulut sağlayıcıların (AWS, GCP) boştaki sunucularını %70-80 indirimle kiraladıkları **Spot** sunucuları, kesintiye toleransı olan test, kuyruk veya worker podları için kullanmak maliyetleri çok büyük oranda düşürür.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [finops_ve_maliyet_optimizasyonu_manifest_2.yaml](../Manifests/10_platform/finops_ve_maliyet_optimizasyonu_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

### Strateji 3: Namespace Kaynak Kotaları (ResourceQuota)

Ekiplerin kontrolsüzce büyük kaynaklar tüketmesini engellemek için isim alanlarına sınır getirilmesi:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [finops_ve_maliyet_optimizasyonu_manifest_3.yaml](../Manifests/10_platform/finops_ve_maliyet_optimizasyonu_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

### Strateji 4: KEDA ile Sıfıra Ölçekleme (Scale-to-Zero)

Eğer bir uygulama sadece kuyruktan (Örn: RabbitMQ) iş okuyorsa ve kuyruk boşsa, bu uygulamayı sıfır kopyaya (`replicas: 0`) çekerek kaynak harcamasını sıfırlayabilirsiniz.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [finops_ve_maliyet_optimizasyonu_manifest_4.yaml](../Manifests/10_platform/finops_ve_maliyet_optimizasyonu_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

### Strateji 5: Karpenter ile Akıllı Node Ölçekleme

Eski tip Cluster Autoscaler yerine AWS için geliştirilen **Karpenter**, podların kaynak ihtiyaçlarına bakar ve saniyeler içinde tam o boyutlara uygun (right-sized) en ucuz sunucuyu (Spot veya On-Demand) AWS'den kiralayarak kümeye ekler.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [finops_ve_maliyet_optimizasyonu_manifest_5.yaml](../Manifests/10_platform/finops_ve_maliyet_optimizasyonu_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. FinOps Olgunluk Modeli (FinOps Maturity Model)

1. **Crawl (Emekleme):** Kubecost kurulur, hangi ekibin ne kadar harcadığı şeffaf bir şekilde görünür hale getirilir.
2. **Walk (Yürüme):** Tag politikaları zorunlu kılınır, isim alanlarına (namespaces) kotalar (ResourceQuota) konur.
3. **Run (Koşma):** VPA önerileri `Auto` moda alınır, Karpenter + Spot sunucu geçişleri tamamlanır.
4. **Fly (Uçma):** FinOps şirket kültürüne dönüşür. Her ekip kendi maliyetinden sorumludur (Chargeback / Bütçe kesintileri).

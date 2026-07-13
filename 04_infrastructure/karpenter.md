# Karpenter: Yeni Nesil ve Hızlı Düğüm Sağlayıcı

AWS tarafından geliştirilen ve açık kaynak kodlu olan **Karpenter**, geleneksel Cluster Autoscaler'a alternatif olarak tasarlanmış modern bir Kubernetes düğüm (node) sağlayıcısıdır. 2026 bulut yerleşik (cloud-native) standartlarında, özellikle AWS ortamlarında hızlı ve akıllı ölçekleme için endüstri standardı haline gelmiştir.

---

## 1. Karpenter vs. Cluster Autoscaler Karşılaştırması

Geleneksel Cluster Autoscaler bulutun "Auto Scaling Groups (ASG)" veya "Virtual Machine Scale Sets" mekanizmalarına bağımlıdır. Bu durum ciddi yavaşlıklara ve esneklik kayıplarına yol açar.

| Özellik | Cluster Autoscaler | Karpenter |
| :--- | :--- | :--- |
| **Grup Bağımlılığı** | ASG grupları tanımlanmak zorundadır. | Grup bağımsızdır (groupless). Düğüm şablonunu dinamik yönetir. |
| **Sunucu Açılma Hızı** | 3 - 5 dakika | 30 - 60 saniye |
| **Düğüm Seçim Zekası** | Sabit ASG şablonundan ne varsa onu açar. | Bekleyen pod'un ihtiyacına göre en ucuz ve ideal VM tipini seçer. |
| **Konsolidasyon** | Sınırlı ve yavaş birleştirme yapar. | Düşük kapasiteli düğümleri otomatik tespit edip pod'ları birleştirir. |

---

## 2. Karpenter Nasıl Çalışır?

Karpenter, Kubernetes API'si ile doğrudan entegredir ve `Pending` (bekleyen) pod'ları izlemek için Scheduler'ı bypass etmez, onunla birlikte çalışır:

1. **İhtiyaç Analizi:** HPA pod sayısını artırdığında ve sunucuda yer kalmadığında pod'lar `Pending` durumuna düşer.
2. **Doğrudan VM Talebi:** Karpenter pod'ların talep ettiği kaynakları (CPU, RAM, GPU) ve affinity kurallarını analiz eder. Bulut sağlayıcının API'si ile doğrudan konuşarak en uygun VM'yi (örneğin AWS EC2) satın alır.
3. **Just-in-Time Provisioning:** Sunucu ayağa kalktığı anda işletim sistemi hazır hale gelir gelmez pod'lar saniyeler içinde içine yerleştirilir.

---

## 3. Karpenter Yapılandırması: NodePool ve EC2NodeClass

Karpenter, iki adet Özel Kaynak Tanımı (CRD) kullanarak yapılandırılır:

* **`NodePool`:** Düğüm sınırlarını, hangi pod'ların buraya yerleşebileceğini (labels, taints), hangi düğüm boyutlarına izin verileceğini ve konsolidasyon (maliyet birleştirme) kurallarını belirler.
* **`EC2NodeClass`:** AWS'ye özgü altyapı ayarlarını (Subnet'ler, Security Group'lar, AMI tipi ve disk boyutları) tanımlar.

📌 **Örnek Yapılandırma Manifesti:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [karpenter_manifest_1.yaml](../Manifests/04_infrastructure/karpenter_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Konsolidasyon (Consolidation) ve FinOps

Karpenter'ın en büyük güçlerinden biri, maliyet optimizasyonudur (FinOps).

* **Düğüm Birleştirme:** Eğer kümede iki adet %30 dolu düğüm varsa, Karpenter pod'ları tek bir düğümde toplar ve boşta kalan ikinci sunucuyu AWS üzerinden kapatır.
* **Spot/On-Demand Geçişi:** Spot instance kesintisi (Spot Interruption) uyarısı aldığında, Karpenter 2 dakikalık süre içinde pod'ları yeni bir On-Demand düğüme güvenli şekilde tahliye eder.

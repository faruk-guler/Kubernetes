# Bulut Yönetimli Kubernetes (Managed Kubernetes)

Kubernetes kurulumu (özellikle Control Plane bileşenlerinin ve `etcd` veritabanının yüksek erişilebilirlikli (HA) şekilde yapılandırılması) oldukça zahmetli ve uzmanlık gerektiren bir süreçtir ("Kubernetes The Hard Way" yaklaşımı).

Modern mimaride şirketlerin %80'inden fazlası, Control Plane yönetimini doğrudan bulut sağlayıcılarına devretmeyi tercih eder. Bu hizmet modeline **Managed Kubernetes (Yönetimli Kubernetes)** veya **CaaS (Container as a Service)** denir.

---

## 1. Managed Kubernetes Ne Anlama Gelir?

Yönetimli bir Kubernetes hizmetinde sorumluluklar bulut sağlayıcısı ile sizin aranızda bölünür (Shared Responsibility Model):

* **Bulut Sağlayıcısının Sorumluluğu:** API Server, Scheduler, Controller Manager ve etcd (Control Plane). Çökmelere karşı yedekleme, versiyon güncellemeleri ve güvenlik yamaları onların sorumluluğundadır. Master node'ları göremez veya doğrudan SSH ile bağlanamazsınız.
* **Müşterinin (Sizin) Sorumluluğunuz:** Worker Node'lar (işçi sunucular), üzerlerinde çalışan Pod'lar, ağ politikaları (Network Policies) ve kimlik doğrulama (RBAC) ayarları.

---

## 2. Devlerin Karşılaştırması: EKS vs. GKE vs. AKS

Pazardaki en büyük üç bulut sağlayıcısının Kubernetes çözümleri temel standartlarda (CNCF uyumlu) aynı olsa da, arka planda ciddi entegrasyon ve otomasyon farkları taşırlar.

| Özellik / Platform | Amazon EKS (Elastic Kubernetes Service) | Google GKE (Google Kubernetes Engine) | Azure AKS (Azure Kubernetes Service) |
| :--- | :--- | :--- | :--- |
| **Pazar Payı ve Olgunluk** | En yüksek pazar payı. Kurumsal kullanımda lider. | En yüksek olgunluk. K8s Google çıkışlı olduğu için özellikler ilk buraya gelir. | Hızlı büyüyen, kurumsal Microsoft ekosistemiyle sıkı entegre. |
| **Control Plane Ücreti** | Saatlik ücretli (Aylık ~$70/cluster). | Temel (Zonal) ücretsiz, Standart/Autopilot (Aylık ~$70/cluster). | Temel ücretsiz, Uptime SLA istenirse ücretli. |
| **Node Ölçeklendirme** | Cluster Autoscaler veya Karpenter (çok hızlı) kullanılır. | Native (doğal) ve çok akıcı bir ölçeklendirme motoru var. | Virtual Machine Scale Sets (VMSS) üzerinden çalışır. |
| **Sunucusuz (Serverless) Çalışma**| AWS Fargate destekli. Node yönetmeden Pod çalıştırılabilir. | GKE Autopilot modu. Düğüm (Node) bilinci yoktur, tamamen soyuttur. | Azure Container Apps / ACI entegrasyonu. |
| **Sürüm Güncellemeleri** | Genellikle manuel tetiklenir, muhafazakardır (eski sürümleri uzun süre destekler). | En hızlı güncellenen (otomatik) platformdur. Yeni özelliklere hemen kavuşursunuz. | Orta düzey otomatik güncelleme yeteneği. |

### GKE Autopilot ve AWS Fargate (Serverless Kubernetes)

Geleneksel yönetilen kümelerde Master Node'ları bulut yönetse bile, Worker Node'larınızı (EC2 vb.) sizin seçmeniz, kapasitelerini belirlemeniz ve işletim sistemi (AMI) yamalarını yapmanız gerekir.

**Serverless Kubernetes** modelinde ise Worker Node kavramı ortadan kalkar. Siz sadece Pod YAML'ınızı gönderirsiniz; bulut sağlayıcısı o Pod'un çalışacağı CPU/RAM kadar arka planda anlık bir kaynak tahsis eder ve sadece Pod'un saniye bazında çalıştığı süre kadar fatura keser.

---

## 3. Üreticiye Bağımlılık (Vendor Lock-in) ve Gizli Maliyetler

Managed Kubernetes kullanmak kurulumu kolaylaştırsa da bazı tuzaklar barındırır:

1. **Ağ ve Çıkış (Egress) Maliyetleri:** Bulut sağlayıcıları kümeye gelen trafikten (Ingress) değil, kümeden dışarı çıkan trafikten (Egress) yüksek ücretler talep eder. Farklı availability zone'lar (AZ) arası haberleşen mikroservisler bile fatura üretir.
2. **Özel Servislere Bağımlılık:** Eğer uygulamanızı AWS IAM (Kimlik Yönetimi) servisine, Amazon RDS veritabanına veya Azure KeyVault servisine aşırı entegre ederseniz, yarın Google Cloud'a geçmeniz gerektiğinde Kubernetes üzerindeki Pod'larınızı taşısanız bile bu dış servisleri taşıyamazsınız. Bu durum Vendor Lock-in (Bağımlılık) yaratır.

### Çözüm: Agnostik (Bağımsız) Mimari

Tam bağımsızlık için `Crossplane` gibi araçlar kullanarak bulut kaynaklarını Kubernetes üzerinden provision edebilir veya Multi-Cloud (Çoklu Bulut) araçlarıyla (`Karmada` veya `Azure Arc`) yükünüzü sağlayıcılar arasında dengeleyebilirsiniz.

---

## Özet

Bulut yönetimi Kubernetes kullanmak, ekibinizi "altyapı kurma" hamallığından kurtarıp doğrudan "ürün geliştirme" işine odaklanmalarını sağlar. Yeni başlayan bir girişim (startup) veya büyük bir şirket için EKS, GKE veya AKS ile yola çıkmak, kendi Bare-metal kümenizi (Kubeadm/RKE2) kurmaktan çok daha rasyonel ve güvenli bir adımdır.

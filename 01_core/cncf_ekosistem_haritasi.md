# CNCF Ekosistemi Haritası

Cloud Native Computing Foundation (CNCF), Kubernetes etrafındaki 1000'den fazla projeyi barındırır. Bu bölüm, "Hangi kategoride hangi araç ne işe yarıyor ve hangisini seçmeliyiz?" sorusunun cevabını verir.

---

## CNCF Olgunluk Seviyeleri (Project Maturity Levels)

CNCF bünyesindeki projeler gelişim düzeylerine göre üç gruba ayrılır:

* **Graduated (Mezun):** Üretim (production) ortamlarında yaygın olarak kabul görmüş, geniş bir geliştirici topluluğuna sahip ve olgunluğunu kanıtlamış projelerdir (Örn: Kubernetes, Prometheus).
* **Incubating (Kuluçka):** Aktif olarak geliştirilen ve üretim ortamlarında kullanımı giderek artan projelerdir (Örn: Karpenter, HNC).
* **Sandbox (Kum Havuzu):** Deney aşamasında olan, yenilikçi ancak henüz üretim standartlarında tam olarak doğrulanmamış erken aşama projeleridir.

---

## 1. Konteyner Orkestrasyonu (Orkestrasyon)

| Araç | Durum | Açıklama |
|:-----|:------|:---------|
| **Kubernetes** | Graduated | Konteyner orkestrasyonunun fiili endüstri standardı. |
| **Crossplane** | Graduated | Kubernetes API'sini kullanarak bulut altyapı kaynaklarını (RDS, S3 vb.) yöneten IaC kontrol düzlemi. |

---

## 2. Konteyner Çalışma Zamanı (Container Runtime)

| Araç | Durum | Açıklama |
| :----- | :------ | :--------- |
| **containerd** | Graduated | Kubernetes'in varsayılan, yüksek performanslı ve hafif konteyner çalışma zamanı. |
| **CRI-O** | Graduated | OCI standartlarına tam uyumlu, özellikle Red Hat OpenShift ekosisteminde yaygın kullanılan hafif çalışma zamanı. |
| **gVisor** | Sandbox | Google tarafından geliştirilen, konteyner ile işletim sistemi arasına güvenli bir kullanıcı alanı (user-space) çekirdeği koyarak izolasyon sağlayan sandbox çözümü. |
| **Kata Containers** | - | Konteynerleri donanım seviyesinde izole edilmiş hafif mikro-sanal makineler (microVMs) içinde çalıştıran güvenlik katmanı. |

---

## 3. Ağ Oluşturma ve Servis Ağı (Networking & Service Mesh)

| Araç | Durum | Ne Zaman Tercih Edilmeli? |
| :----- | :------ | :--------- |
| **Cilium** | Graduated | eBPF teknolojisini kullanan, yüksek performanslı, gelişmiş güvenlikli ve kube-proxy'ye ihtiyaç duymayan 2026 yılı standart CNI. |
| **Calico** | - | Geleneksel, kendini kanıtlamış ve BGP yönlendirme protokolü desteğiyle kurumsal veri merkezlerinde tercih edilen CNI. |
| **Kube-Router** | - | Go ile yazılmış, minimal ve hafif, edge/kısıtlı donanımlar için ağ çözümü. |
| **Istio** | Graduated | Geniş özellik setine sahip, mTLS şifrelemesi, trafik yönetimi ve politika kontrolleri sunan popüler servis ağı (service mesh). |
| **Linkerd** | Graduated | Rust ile yazılmış, son derece hafif, düşük kaynak tüketen ve kullanım kolaylığı odaklı servis ağı. |
| **Envoy** | Graduated | Service mesh araçlarının (Istio vb.) altında veri geçişini (data plane) yöneten yüksek performanslı L7 proxy. |
| **CoreDNS** | Graduated | Kubernetes küme içi isim çözme ve DNS servisinin varsayılan sağlayıcısı. |
| **MetalLB** | - | Bulut sağlayıcısı olmayan bare-metal veya şirket içi (on-premise) kümelerde LoadBalancer IP ataması sağlayan ağ çözümü. |

```
CNCF Ağ Çözümü Seçim Kılavuzu:
  - Küçük ve Basit Küme: Calico veya Cilium (Hafif modda)
  - Performans ve Güvenlik Odaklı Canlı Ortam: Cilium (eBPF)
  - Çok Kapsamlı Kurumsal Service Mesh: Istio
  - Düşük Bellek ve CPU Tüketimi: Linkerd
```

---

## 4. Depolama (Storage)

| Araç | Durum | Ne Zaman Tercih Edilmeli? |
| :----- | :------ | :--------- |
| **Rook** | Graduated | Dağıtık depolama sistemi Ceph'i Kubernetes operatörüne dönüştürerek on-premise kümelerde EBS benzeri dinamik disk sağlar. |
| **Longhorn** | Graduated | SUSE tarafından geliştirilen, kolay kurulan ve yönetilen, yedekleme entegreli cloud-native block depolama çözümü. |
| **OpenEBS** | Graduated | Konteyner tabanlı veri depolama motoru (özellikle Mayastor motoru ile NVMe üzerinden yüksek performans). |
| **Velero** | - | Küme manifestlerini ve kalıcı disk verilerini (PV) bulut depolama alanlarına yedekleme aracı. |

---

## 5. Gözlemlenebilirlik (Observability)

| Araç | Durum | Görevi |
| :----- | :------ | :------- |
| **Prometheus** | Graduated | Zaman serisi veri tabanı, metrik toplama (pull modeli) ve uyarı mekanizması (Alertmanager). |
| **Grafana** | - | Metrik, log ve izleme verilerini tek arayüzde birleştiren görselleştirme paneli. |
| **OpenTelemetry** | Graduated | Metrik, log ve trace verilerinin standartlaştırılmış şekilde toplanmasını sağlayan endüstri standardı SDK ve Collector mimarisi. |
| **Thanos** | Incubating | Birden fazla kümedeki Prometheus verilerini merkezi hale getiren ve uzun dönemli ucuz depolamayı (S3/GCS) sağlayan eklenti. |
| **Fluent Bit** | Graduated | Çok düşük kaynak tüketen, yüksek performanslı log toplayıcı ve yönlendirici (Fluentd projesinin hafif halefi). |

---

## 6. Güvenlik ve Uyum (Security)

| Araç | Durum | Görevi |
| :----- | :------ | :------- |
| **Falco** | Graduated | Çekirdek (kernel) seviyesinde çağrıları dinleyen çalışma zamanı (runtime) tehdit algılama sistemi. |
| **OPA / Gatekeeper** | Graduated | Rego dili ile Kubernetes kaynaklarının en iyi pratiklere uygunluğunu denetleyen politika motoru. |
| **Kyverno** | Graduated | Herhangi bir dil bilmeden, sadece Kubernetes YAML formatında güvenlik ve atama politikaları tanımlayan K8s-native politika motoru. |
| **cert-manager** | - | Küme içindeki uygulamaların TLS (SSL) sertifikalarını otomatik üreten ve Let's Encrypt entegrasyonu sağlayan araç. |
| **SPIFFE / SPIRE** | Graduated | Çoklu bulut ortamlarında podlara statik şifre/sertifika vermeden kriptografik güvenli kimlik (identity) atama motoru. |
| **Sigstore / Cosign** | - | Konteyner imajlarını imzalayarak güvenli tedarik zinciri (supply chain) oluşturan araç. |
| **Trivy** | - | İmaj tarama, yazılım bağımlılıkları açıkları (CVE) ve Kubernetes manifest hatalarını bulan linter. |

---

## 7. GitOps ve Dağıtım (CI/CD)

| Araç | Durum | Açıklama |
| :----- | :------ | :--------- |
| **Argo CD** | Graduated | Git deposundaki kodun durumunu küme ile eşitleyen, zengin web arayüzlü (GUI) GitOps aracı. |
| **Flux** | Graduated | Tamamen Kubernetes nesneleriyle yönetilen, kod odaklı ve çok kiracılı (multi-tenant) alternatif GitOps motoru. |
| **Helm** | Graduated | Kubernetes manifest şablonları hazırlamayı ve bunları tek komutla paket olarak dağıtmayı sağlayan paket yöneticisi. |
| **Kustomize** | - | YAML dosyalarını şablonlaştırmadan, overlay (üzerine yazma) yöntemiyle farklı ortamlar (dev/prod) için özelleştiren araç. |

---

## 8. 2026 Yılı İçin Modern Üretim (Production) Yığın Önerisi

Bir Kubernetes kümesi kurarken aşağıdaki araç yığınını (stack) tercih etmeniz modern standartları yakalamanızı sağlar:

* **İşletim Sistemi (OS):** Ubuntu Server veya Talos Linux (Güvenli, immutable)
* **Kurulum:** EKS/GKE (Bulutta) veya RKE2 / Talos Linux (On-Premise)
* **Ağ (CNFI):** Cilium (eBPF desteğiyle kube-proxy bypass)
* **SSL/TLS Yönetimi:** Cert-Manager
* **Gözlemlenebilirlik:** Grafana LGTM Yığını (Loki, Grafana, Tempo, Mimir)
* **Güvenlik Politikaları:** Kyverno
* **Yedekleme:** Velero

---

## Özet

CNCF manzarası (landscape) 1000'den fazla araç içerir ve **tüm bu araçları bilmek imkansızdır.** Önemli olan kategorileri anlamak ve her kategoride kendini kanıtlamış olan 1-2 araca derinlemesine hakim olmaktır. Bu ansiklopedi boyunca burada adı geçen tüm kritik araçların kurulumlarını ve kullanım senaryolarını detaylarıyla inceleyeceğiz.

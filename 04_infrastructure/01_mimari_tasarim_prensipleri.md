# Kubernetes Mimari Tasarım Prensipleri (Architecture Design Principles)

Sistem mühendisliği, mükemmel çözümler bulma sanatı değil, **Ödünleşim (Trade-off / Taviz)** yönetme sanatıdır. Kubernetes dünyasında hiçbir mimari karar bedava veya mutlak olarak "en doğrusudur" diyerek alınamaz.

Güvenliği en üst seviyeye çıkarmak isterseniz ağ ve erişim karmaşıklığıyla boğuşursunuz; yüksek performans isterseniz bulut faturalarını kabartırsınız; yüksek kullanılabilirlik (HA) hedeflerseniz yönetim ve yedekleme yükünü artırırsınız.

Mimarın asıl görevi, kusursuz bir sistem tasarlamak değil, eldeki kaynaklar (bütçe, zaman ve insan gücü) doğrultusunda en optimize ve sürdürülebilir dengeyi kurmaktır. Bu bölüm, cluster tasarımında verilecek kritik kararları, mimari kalıpları ve bu kararların getirdiği ödünleşimleri ele alır.

---

## 1. Küme (Cluster) Topolojisi Tasarımı

### Tek Büyük Küme (Large Shared Cluster) vs. Çoklu Küme (Multi-Cluster)

Uygulamalarınızı tek bir büyük kümede mi yoksa bağımsız küçük kümelerde mi çalıştıracağınıza karar verirken şu ödünleşimler göz önünde bulundurulmalıdır:

```
Tek Büyük Küme:
  ✅ Operasyonel Basitlik: Tek bir Control Plane, tek bir izleme ve loglama sistemi yönetilir.
  ✅ Düşük Maliyet: Sunucu israfı azdır, kaynak paylaşımı verimlidir.
  ❌ Geniş Etki Alanı (Blast Radius): Kümedeki ciddi bir hata veya çökme tüm uygulamaları etkiler.
  ❌ Zayıf İzolasyon: Ekipler ve ortamlar arası tam izolasyon sağlamak zordur.
  🎯 İdeal Olduğu Durumlar: Küçük ve orta ölçekli ekipler, tekil ürün yapıları.

Çoklu Küme Yapısı (Multi-Cluster):
  ✅ Güçlü İzolasyon: Test (Dev), Ön Canlı (Staging) ve Canlı (Prod) ortamları tamamen ayrıdır.
  ✅ Dar Etki Alanı: Bir kümenin çökmesi diğerlerini etkilemez.
  ✅ Sürüm Bağımsızlığı: Kümeler farklı Kubernetes sürümlerinde çalıştırılabilir.
  ❌ Yüksek Operasyonel Yük: Onlarca Control Plane ve yedekleme sisteminin yönetimi gerekir.
  ❌ Yüksek Maliyet: Her küme için ayrı master node'lar ve ek yönetim servisleri faturalandırılır.
  🎯 İdeal Olduğu Durumlar: Büyük ölçekli kurumsal yapılar, sıkı regülasyonlar (PCI-DSS, KVKK).
```

---

## 2. Ağ Mimarisi ve Trafik Akışı (Traffic Flow)

### Ingress ve Egress Trafik Akış Şeması

Trafik, dış dünyadan (North-South) podlara ulaşana kadar şu katmanlardan geçer:

```
İnternet (Müşteri Talebi)
    │
    ▼
[Cloud Load Balancer / Bare-Metal MetalLB] (Dış IP ataması)
    │
    ▼
[Ingress Controller veya Gateway API] (NGINX, Traefik, Cilium Ingress)
    │
    ▼
[Kubernetes Service — ClusterIP] (Küme içi yük dengeleme ve yönlendirme)
    │
    ▼
[Hedef Pod] (Uygulama Konteyneri)
    │
    ▼
[Küme İçi Diğer Servisler — East-West Trafik] (Ağ Politikaları ile denetlenir)
```

* **North-South Trafik (Dış-İç Trafik):** Küme dışından gelen veya dışarıya giden trafiktir. Güvenliği WAF, DDoS korumaları ve TLS sonlandırma (SSL termination) ile sağlanır.
* **East-West Trafik (İç-İç Trafik):** Podların kendi arasında yaptığı iletişimdir. Güvenliği **NetworkPolicy** ve Service Mesh (örneğin **Istio** ile mTLS şifrelemesi) kullanılarak sağlanmalıdır.

---

## 3. Stateful vs. Stateless Mimari Kararları

Kubernetes podları doğası gereği geçicidir (**ephemeral**). Bir hata anında pod yok edilir ve başka düğümde temiz bir kopyası açılır.

* **Stateless (Durumsuz - Tercih Edilen):** Podun kendi içinde hiçbir veri (state) tutmadığı modeldir. Uygulama verileri harici bir veritabanında (RDS, Cloud SQL vb.) saklanır. Ölçeklenmesi son derece kolaydır, hızlı açılır ve kapanır.
* **Stateful (Durumlu - Zorunlu Hallerde):** Podun çalışmak için kalıcı bir veriye (Persistent Volume) ihtiyaç duyduğu modeldir (Veritabanları, kuyruk sistemleri). Yönetimi zordur, yedekleme stratejisi ve disk mimarisi (CSI) gerektirir.
* **Mimari Altın Kural:** Mümkünse veritabanı gibi stateful iş yüklerinizi Kubernetes dışında (AWS RDS gibi yönetilen servislerde) tutun. Sadece stateless web/API uygulamalarınızı Kubernetes'e taşıyarak operasyonel yükünüzü azaltın.

---

## 4. Derinlemesine Savunma (Defense in Depth) Güvenlik Katmanları

Güvenli bir Kubernetes mimarisi, tek bir kale duvarı yerine birbirini destekleyen çoklu katmanlardan (defense in depth) oluşmalıdır:

```
[Katman 1: Ağ (CNI)]      ──► NetworkPolicy ile podlar arası yalıtım (Sadece A, B ile konuşabilir).
[Katman 2: Servis Ağı]    ──► Service Mesh (Istio) ile podlar arası trafiğin mTLS ile şifrelenmesi.
[Katman 3: Pod Güvenliği] ──► SecurityContext (Podların root yetkisi olmadan çalıştırılması).
[Katman 4: Erişim (RBAC)] ──► En az yetki prensibi (Least Privilege) ile API erişim kısıtlaması.
[Katman 5: Sırlar (Secrets)]──► Şifrelerin Vault veya External Secrets ile şifreli yönetilmesi.
[Katman 6: İmaj Güvenliği]──► Trivy ile zafiyet taraması ve Cosign ile imzalanmış güvenli imajlar.
[Katman 7: API Denetimi]  ──► Kyverno gibi politika motorlarıyla kuralsız kaynakların engellenmesi.
[Katman 8: Çalışma Zamanı]──► Falco ile işletim sistemi düzeyinde anomali tespiti.
```

---

## 5. Kapasite Planlama ve Düğüm (Node) Seçimi

### Küçük Düğümler mi? Büyük Düğümler mi?

| Özellik | Küçük Düğümler (Örn: 4 vCPU, 16GB) | Büyük Düğümler (Örn: 64 vCPU, 256GB) |
|:---|:---|:---|
| **Düğüm Çökme Etkisi** | 🟢 Düşük etki (Blast radius dar) | 🔴 Yüksek etki (Kapasitenin büyük kısmı gider) |
| **DaemonSet Maliyeti**| 🔴 Yüksek (Her düğümde log/cni podları açılır) | 🟢 Düşük (Daha az düğüm, daha az overhead) |
| **Pod Yerleşim Esnekliği**| 🟢 Kolay (Boşlukları doldurmak kolaydır) | 🔴 Zor (Çok büyük kaynak isteyen podlar sıkışabilir) |
| **Yönetim Kolaylığı** | 🔴 Zor (20 düğümü izlemek ve güncellemek yavaş sürer) | 🟢 Kolay (3-4 düğümün bakımı ve yönetimi hızlıdır) |

* **Öneri:** Üretim ortamlarında iki uçtan da kaçınarak dengeli orta boy sunucular (**16-32 vCPU, 64-128GB RAM**) ve yedek kapasite (headroom) marjı bırakılması en ideal mimari yaklaşımdır.

---

## 6. Felaketten Kurtarma (Disaster Recovery - DR) Mimarisi

DR planı yaparken iki temel parametreye göre karar verilir:

* **RTO (Recovery Time Objective):** Sistemin çöküş anından ne kadar süre sonra tekrar ayağa kalkması gerekiyor? (Hedef süre).
* **RPO (Recovery Point Objective):** Çökme anında en fazla ne kadarlık veri kaybını (örneğin son 1 saatlik) tolere edebiliriz?

```
Strateji A: Active-Active (RTO ≈ 0, RPO ≈ 0)
  - Çoklu bölgede (multi-region) senkron çalışan kümeler. (Son derece pahalı ve ağ gecikmesi yüksektir).

Strateji B: Active-Passive Standby (RTO < 1 saat, RPO < 1 saat)
  - Velero ile saatlik yedekleme ve hazır bekleyen boş bir yedek küme.

Strateji C: Cold Recovery (RTO < 4 saat, RPO < 24 saat)
  - Günlük yedekleme. Bir felaket anında IaC (Terraform) ile kümeyi sıfırdan kurup Velero yedeğinden geri yükleme.
```

---

## 7. Mimari Karar Defteri (Architecture Decision Record - ADR)

Mimari kararlar alınırken, o kararın neden alındığı, hangi alternatiflerin elendiği ve hangi ödünleşimlerin (trade-offs) kabul edildiği mutlaka belgelenmelidir.

### Örnek ADR Şablonu

```markdown
# ADR-001: CNI Tercihi ve Kube-Proxy Bypass

## Durum
Kabul Edildi (2026-03-12)

## Bağlam
Küme genelinde yüksek trafik altında ağ gecikmelerini azaltmak ve podlar arası güvenliği daha sıkı denetlemek istiyoruz.

## Karar
Kümede varsayılan CNI olarak **Cilium** kullanılacaktır. `kube-proxy` devre dışı bırakılarak eBPF modu aktif edilecektir.

## Gerekçe
- eBPF sayesinde iptables kurallarının getirdiği CPU yükünden kurtularak ağ performansında %30 kazanç elde edilir.
- Hubble arayüzü ile ağ trafiği görselleştirilebilir.
- NetworkPolicy denetimleri çekirdek (kernel) seviyesinde yapılır.

## Ödünleşimler (Trade-offs)
- Cilium'un kurulumu ve yönetimi varsayılan basit CNI'lara (örneğin flannel) göre daha karmaşıktır.
- Ekibin eBPF ve Hubble kullanımı konusunda eğitilmesi gerekmektedir.
```

---

## Özet

Kubernetes mimarisi tasarlamak, sürekli bir denge arayışıdır. Her kararın bir maliyeti ve kazancı vardır. Güçlü bir mimar, bu kararları **ADR** belgeleriyle kayıt altına alır, riskleri **Savunma Katmanları (Defense in Depth)** ile dağıtır ve felaket kurtarma stratejilerini iş gereksinimlerine göre optimize eder.

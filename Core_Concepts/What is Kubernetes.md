# Kubernetes Nedir?

## Bir Konteyner Limanı ve Dümencinin Hikayesi

Yazılım dünyasında konteynerler (Docker imajları), her şeyi standart boyutlardaki metal konteynerlere sığdırarak nakliyeyi kolaylaştıran deniz taşımacılığı devrimine benzer. Bir konteyner içine uygulamanızı, bağımlılıklarını ve çalışma ortamını koyarsınız; böylece "benim bilgisayarımda çalışıyordu, sunucuda neden çalışmıyor?" derdi son bulur.

Ancak gerçek sorun, limana binlerce konteyner yanaştığında başlar:
* Hangi konteyner hangi gemiye (sunucuya) yüklenecek?
* Konteynerlerden biri hasar görürse (uygulama çökerse) yerine yenisi nasıl konacak?
* Limandaki vinçler ve elektrik kaynakları (RAM/CPU) konteynerler arasında nasıl paylaştırılacak?
* Gece saat 03:00'te bir konteyner durduğunda bunu kim fark edip uykusundan uyanacak?

İşte bu devasa limanın yönetimini üstlenen, hangi vinci nereye yönlendireceğini bilen, fırtınalarda gemilerin dengesini koruyan ve tüm limanı tek bir merkezden yöneten o tecrübeli **Dümenci (Yunanca: Kubernetes / K8s)** tam da bu yüzden doğmuştur. Kubernetes, tek tek konteynerleri manuel yönetmek yerine, tüm limanı (cluster) sizin adınıza yöneten akıllı bir otomasyon orkestrasıdır.

---

## Tanım ve Tarihçe

**Kubernetes**, konteyner iş yüklerini otomatik olarak dağıtan, ölçeklendiren ve yöneten açık kaynaklı bir orkestrasyon platformudur. Google tarafından iç kullanım için geliştirilen ve binlerce sunucuyu yöneten **Borg** sisteminden elde edilen 15 yıllık tecrübeyle tasarlanıp 2014'te açık kaynak olarak piyasaya sürülmüştür. 2016'da **Cloud Native Computing Foundation (CNCF)** bünyesine teslim edilerek bulut bilişim dünyasının fiili standardı haline gelmiştir.

---

## Kubernetes Neden Gereklidir?

Modern yazılım geliştirmede monolitik (tek parça) mimariler yerini onlarca veya yüzlerce küçük servise (mikro servis) bırakmıştır. Bu servislerin her birini:

- Bir sunucuya elle kurmak ve konfigüre etmek
- Çalışma durumlarını sürekli izlemek ve çöktüklerinde yeniden başlatmak
- Trafik artışında kaynakları (RAM/CPU) izleyerek ölçeklendirmek
- Yeni versiyonları yüklerken sistemi kesintiye uğratmadan güncellemek ve gerekirse geri almak

...insan gücüyle yapılması son derece karmaşık ve hata eğilimli süreçlerdir. Kubernetes tüm bu karmaşık operasyonel adımları **otomatize** eder.

---

## Kubernetes'in Temel Yetenekleri

| Yetenek | Açıklama |
|:---|:---|
| **Self-Healing (Kendi Kendini Onarma)** | Çöken veya yanıt vermeyen pod'ları otomatik olarak yeniden başlatır, node çöktüğünde pod'ları başka node'a taşır. |
| **Auto-Scaling (Otomatik Ölçekleme)** | CPU/RAM yükü arttığında pod sayısını (HPA) veya cluster'daki fiziksel sunucu sayısını (CA) otomatik artırır. |
| **Rolling Updates (Kesintisiz Güncelleme)** | Uygulamaları kullanıcı trafiğini kesmeden sırayla günceller; hata durumunda otomatik eski sürüme döner (rollback). |
| **Service Discovery & Load Balancing** | Konteynerlere kendi IP adreslerini ve tek bir DNS adı verir. Trafiği konteynerler arasında dengeli dağıtır. |
| **Secret & Config Management** | Şifreleri, API key'leri ve konfigürasyonları uygulama imajından bağımsız, şifreli ve güvenli bir şekilde saklar. |
| **Storage Orchestration** | Local depolama, AWS EBS, GCP Persistent Disk, NFS veya Ceph gibi sistemleri konteynerlere otomatik mount eder. |

---

## 2026'da Kubernetes: Ne Değişti?

2026 yılında Kubernetes kullanımı birkaç kritik evrimi tamamlamış ve eski karmaşık yaklaşımları modernize etmiştir:

- **eBPF (Cilium):** Geleneksel ve hantal olan `kube-proxy + iptables` ağ yönlendirmesi yerini tamamen eBPF (Extended Berkeley Packet Filter) tabanlı Cilium'a bırakmıştır.
- **Gateway API:** Eski `Ingress` kaynağı yerini daha modüler ve yetenekli olan `Gateway API` v1 standartlarına devretmiştir.
- **GitOps standardı:** Manuel `kubectl apply` işlemleri yerini tamamen Git depolarını kaynak alan ve sürekli senkronizasyon sağlayan ArgoCD veya Flux gibi GitOps araçlarına bırakmıştır.
- **Immutable OS:** Control Plane ve Worker node'lar üzerinde paket yöneticisi bile barındırmayan, sadece Kubernetes çalıştırmak üzere optimize edilmiş salt okunur işletim sistemleri (Talos Linux vb.) yaygınlaşmıştır.
- **Policy-as-Code:** Eski Pod Security Policies (PSP) tamamen kaldırılmış; cluster güvenliği Kyverno ve CEL (Common Expression Language) ile YAML dosyaları üzerinden yönetilir hale gelmiştir.

---

## Kubernetes Nasıl Çalışır? (Genel Bakış)

```
┌─────────────────────────────────────────────┐
│              CONTROL PLANE                  │
│  ┌──────────┐  ┌──────┐  ┌───────────────┐  │
│  │api-server│  │ etcd │  │scheduler/CM   │  │
│  └──────────┘  └──────┘  └───────────────┘  │
└──────────────────┬──────────────────────────┘
                   │ (API)
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│Worker 1  │  │Worker 2  │  │Worker 3  │
│kubelet   │  │kubelet   │  │containerd│
│containerd│  │containerd│  │[Pod][P]  │
│[Pod][P]  │  │[Pod]     │  └──────────┘
└──────────┘  └──────────┘
```

> [!NOTE]
> Control Plane, cluster'ın beynidir ve sistemin durumuyla ilgili kararları alır. Worker Node'lar ise konteynerleri fiilen çalıştıran işçi makinelerdir. 2026 standartlarında etcd, yüksek performans ve güvenlik için Control Plane sunucularından bağımsız bir kümede (external etcd) konumlandırılabilmektedir.

# Kubernetes Nedir?

## 1.1 Tanım ve Tarihçe

**Kubernetes** (Yunanca: "dümenci/kaptan"), konteyner iş yüklerini otomatik olarak dağıtan, ölçeklendiren ve yöneten açık kaynaklı bir orkestrasyon platformudur. Google tarafından iç kullanım için geliştirilen **Borg** sisteminden ilham alınarak 2014'te açık kaynak olarak piyasaya sürülmüştür. 2016'da **Cloud Native Computing Foundation (CNCF)** bünyesine alınmıştır.

## 1.2 Kubernetes Neden Gereklidir?

Modern yazılım geliştirmede uygulamalar onlarca veya yüzlerce küçük servise (mikro servis) bölünmektedir. Bu servislerin her birini:

- Bir sunucuya elle kurmak
- İzlemek, yeniden başlatmak
- Trafik artışında ölçeklendirmek
- Güncellemek ve geri almak

...son derece karmaşık ve hata eğilimli bir süreçtir. Kubernetes tüm bu işlemleri **otomatize** eder.

## 1.3 Kubernetes'in Temel Yetenekleri

| Yetenek | Açıklama |
|:---|:---|
| **Self-Healing** | Çöken pod'ları otomatik yeniden başlatır |
| **Auto-Scaling** | Yük arttığında pod sayısını otomatik artırır |
| **Rolling Updates** | Uygulamaları sıfır kesinti ile günceller |
| **Service Discovery** | Servisler birbirini otomatik bulur |
| **Secret Management** | Şifre ve token'ları güvenli saklar |
| **Storage Orchestration** | Depolama birimlerini otomatik bağlar |
| **Load Balancing** | Trafiği pod'lar arasında dağıtır |

## 1.4 2026'da Kubernetes: Ne Değişti?

2026 yılında Kubernetes kullanımı birkaç kritik evrimi tamamlamıştır:

- **eBPF (Cilium):** Geleneksel `kube-proxy + iptables` yerini tamamen eBPF'e bırakmıştır
- **Gateway API:** `Ingress` kaynağı deprecated yolunda; `Gateway API` v1 (stable) standarttır
- **GitOps:** Manuel `kubectl apply` sadece acil durumlar için; her şey ArgoCD/Flux üzerinden
- **Immutable OS:** Talos Linux, Flatcar gibi salt okunur işletim sistemleri yaygınlaşmıştır
- **Policy-as-Code:** PSP kaldırıldı; Kyverno ve CEL ile politikalar YAML olarak yönetilir

## 1.5 Kubernetes Nasıl Çalışır? (Genel Bakış)

```
┌─────────────────────────────────────────────┐
│              CONTROL PLANE                  │
│  ┌──────────┐  ┌──────┐  ┌───────────────┐  │
│  │api-server│  │ etcd │  │scheduler/CM   │  │
│  └──────────┘  └──────┘  └───────────────┘  │
└──────────────────┬──────────────────────────┘
                   │ (API)
    ┌──────────────┼──────────────┐
    ▼              ▼              ▼
┌──────────┐    ┌──────────┐    ┌──────────┐
│Worker 1  │    │Worker 2  │    │Worker 3  │
│kubelet   │    │kubelet   │    │kubelet   │
│containd  │    │containd  │    │containd  │
│[Pod][P]  │    │[Pod]     │    │[Pod][P]  │
└──────────┘    └──────────┘    └──────────┘
```

> [!NOTE]
> Control Plane, cluster'ın beynidir ve kararları alır. Worker Node'lar ise pod'ları fiilen çalıştırır. 2026 standartlarında etcd, Control Plane'den ayrı (external) kurulabilir.

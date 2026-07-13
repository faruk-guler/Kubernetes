# Kümeler Arası Ağ İletişimi: Submariner ve Cilium ClusterMesh

Çoklu Kubernetes kümesi (Multi-Cluster) çalıştırılan kurumsal altyapılarda, farklı coğrafyalarda veya bulut sağlayıcılarda bulunan pod'ların ve servislerin birbirleriyle en düşük gecikmeyle (low-latency) ve güvenli bir şekilde konuşmasını sağlamak en kritik ağ sorunlarından biridir.

---

## 1. Ağ Problem Tanımı: Çakışan IP Blokları

Genellikle her Kubernetes kümesi kurulurken pod ve servis ağları için benzer iç IP blokları (Örn: `10.244.0.0/16`) kullanılır. Farklı kümelerdeki pod'lar birbirlerine doğrudan IP üzerinden erişmek istediğinde ağ geçitlerinde paket çakışmaları yaşanır.

Bu sorunu çözmek ve kümeler arası kesintisiz L3/L4 ağ katmanı kurmak için iki popüler teknoloji kullanılır: **Submariner** ve **Cilium ClusterMesh**.

```
[ Küme A (IP: 10.244.0.0/16) ] ◄───( L3 Ağ Tüneli / eBPF )───► [ Küme B (IP: 10.248.0.0/16) ]
```

---

## 2. Submariner ile L3 Ağ Tünelleme

Submariner, CNI bağımsız çalışabilen ve kümeler arasında IPSec veya Wireguard tünelleri kuran bir VPN ağ birleştiricidir.

### A. Servis İhracatı (ServiceExport - Küme A üzerinde)

Küme A'da bulunan `orders-service` servisini diğer kümelerin erişimine açmak için:

```yaml
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: orders-service
  namespace: production
```

### B. Servis İçe Alımı (ServiceImport - Küme B üzerinde)

Küme A servisi ihraç ettiği an, Submariner Lighthouse denetleyicisi Küme B üzerinde otomatik olarak bir `ServiceImport` nesnesi oluşturur.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kumeler_arasi_ag_manifest_1.yaml](../Manifests/11_multicluster/kumeler_arasi_ag_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Küme B içindeki pod'lar artık bu servise `orders-service.production.svc.clusterset.local` DNS adresi üzerinden güvenle erişebilir.

---

## 3. Cilium ClusterMesh: eBPF Tabanlı Doğrudan Bağlantı

Eğer tüm kümelerinizde **Cilium CNI** yüklü ise, harici bir tünel aracı kurmadan Cilium'un yerleşik **ClusterMesh** özelliğini aktif edebilirsiniz. ClusterMesh, eBPF kancalarını kullanarak paketleri tünelleme yapmadan doğrudan çekirdek seviyesinde (kernel-level) yönlendirir. Bu sayede maksimum bant genişliği ve sıfıra yakın performans kaybı elde edilir.

### Kurulum Adımları

```bash
# 1. Her iki kümede de ClusterMesh özelliğini aktif edin (Harici LoadBalancer IP'si kullanarak)
cilium clustermesh enable --service-type LoadBalancer --context=cluster-a
cilium clustermesh enable --service-type LoadBalancer --context=cluster-b

# 2. İki kümeyi birbirine bağlayın
cilium clustermesh connect --context=cluster-a --destination-context=cluster-b

# 3. Bağlantı durumunu doğrulayın
cilium clustermesh status --context=cluster-a
```

---

## 4. Global Services (Global Servisler ve Yük Dengeleme)

Cilium ClusterMesh aktif olduğunda, birden fazla kümede çalışan aynı isimli servisleri tek bir **Global Service** altında birleştirebilirsiniz. Bu sayede trafik iki kümedeki pod'lar arasında otomatik olarak paylaştırılır.

### Global Service Yapılandırması

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kumeler_arasi_ag_manifest_2.yaml](../Manifests/11_multicluster/kumeler_arasi_ag_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Global Service Failover (Hata Toleransı) Senaryosu

Global Servis mimarisi, yüksek kullanılabilirlik ve felaket senaryoları için kusursuzdur:

```
[ Kullanıcı İsteği ] ──► [ Küme A - payment-service ]
                                │
          ┌─────────────────────┴─────────────────────┐
   (Küme A podları CANLI)                   (Küme A podları ÇÖKTÜ - Failover)
          ▼                                           ▼
[ Küme A - payment-pod ]                   [ Küme B - payment-pod ] (Ağ tünelinden)
```

1. **Normal Durum:** Küme A'daki kullanıcı istekleri, `io.cilium/service-affinity: "local"` ayarı sayesinde sadece Küme A'daki pod'lara yönlendirilir (Sıfır gecikme).
2. **Hata Anı:** Küme A'daki tüm `payment-processor` pod'ları çöktüğünde veya silindiğinde, Cilium ClusterMesh trafiği kesintisiz bir şekilde Küme B'deki pod'lara yönlendirir. Kullanıcı hiçbir kesinti hissetmez.
3. **Kurtarma:** Küme A pod'ları tekrar ayağa kalktığında trafik otomatik olarak yerel düğümlere geri döner.

---

## 6. Multi-Cluster DNS Federasyonu Yapısı

Çoklu küme yapılarında DNS sorgularını çözmek için **clusterset.local** alan adı standardı kullanılır.

* **Submariner Lighthouse DNS:** Kümeler içinde CoreDNS'e entegre çalışan bir stub-zone olarak kurulur. Sorgulanan DNS `clusterset.local` ile bitiyorsa, Lighthouse sorguyu kendi veritabanındaki `ServiceImport` IP'sine yönlendirir.
* **Cilium ClusterMesh DNS:** Global service kullanıldığında ekstra bir DNS alan adına gerek kalmaz. Geliştirici doğrudan bildiği yerel DNS adresini (`payment-service.production.svc.cluster.local`) çağırmaya devam eder. eBPF katmanı arka planda yük dengelemeyi otomatik çözer.

---

## 7. Submariner ve Cilium ClusterMesh Karşılaştırması

| Özellik | Submariner | Cilium ClusterMesh |
|:---|:---:|:---:|
| **CNI Bağımlılığı** | Bağımsız (Flannel, Calico vb. ile çalışır) | ⚠️ **Cilium CNI zorunludur.** |
| **Performans Overheadi** | Tünel şifrelemesi nedeniyle orta düzeyde | 🟢 Sıfıra yakın (eBPF kernel routing) |
| **Trafik Şifreleme** | Dahili (IPSec / Wireguard) | Dahili (Wireguard / IPsec) |
| **DNS Kullanımı** | `*.clusterset.local` gerektirir | Yerel DNS (`*.cluster.local`) yeterlidir |
| **Otomatik Failover** | Manuel / MCS kurallarına bağlı | ⚡ Tamamen otomatik (Cilium Agent yönetir) |

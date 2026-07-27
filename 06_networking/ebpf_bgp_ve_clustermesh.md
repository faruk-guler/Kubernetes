# eBPF BGP ve Cilium ClusterMesh

Büyük ölçekli kurumsal altyapılarda veya hibrit bulut (hybrid cloud) mimarilerinde, farklı bölgelerdeki (veya farklı bulut sağlayıcılarındaki) Kubernetes kümelerini tek bir düz ağ (flat network) üzerinde birleştirmek gerekebilir.

Klasik çözümlerde bu işlem karmaşık VPN yapılandırmaları ve hantal yönlendirici proxy sistemleri ile yapılırken; **Cilium ClusterMesh** ve eBPF tabanlı **BGP (Border Gateway Protocol)** sayesinde bu bağlantı doğrudan kernel seviyesinde şeffaf (transparent) olarak kurulabilir.

---

## 1. BGP (Border Gateway Protocol) ve Cilium Entegrasyonu

Şirket içi (on-premise) veri merkezlerindeki fiziksel ağ yönlendiricilerinin (Cisco, Juniper vb.) Kubernetes podlarının IP aralıklarını (Pod CIDR) doğrudan tanıyabilmesi için BGP kullanılır. Cilium, ek bir yazılım kurmaya gerek kalmadan eBPF düzeyinde yerleşik BGP desteği sunar.

Cilium 1.16+ sürümü ile gelen yeni **BGP Control Plane v2** (`CiliumBGPClusterConfig`) kaynağı ile BGP peering şu şekilde tanımlanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ebpf_bgp_ve_clustermesh_manifest_1.yaml](../Manifests/05_networking/ebpf_bgp_ve_clustermesh_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

BGP peering başarıyla kurulduktan sonra, veri merkezindeki herhangi bir fiziksel sunucu, arada NAT (Network Address Translation) olmaksızın Kubernetes podlarının IP adreslerine doğrudan erişebilir.

---

## 2. Cilium ClusterMesh ile Çoklu Küme Bağlantısı

Bir Kubernetes kümenizin AWS EKS üzerinde, diğerinin ise kendi veri merkezinizde (On-Premise VMware) çalıştığını düşünelim. **Cilium ClusterMesh**, bu iki bağımsız kümedeki podların ve servislerin birbirleriyle doğrudan ve güvenli bir ağ tüneli üzerinden konuşmasını sağlar.

```
[ Cluster AWS (EKS) ]                               [ Cluster On-Premise ]
  ├── Pod A (10.244.1.5)                              ├── Pod B (10.245.1.8)
  └── Cilium Agent ◄───(Güvenli Tünel: WireGuard)───► └── Cilium Agent
```

### Gereksinimler

1. **Çakışmayan Subnetler:** İki kümenin Pod CIDR ve Service CIDR ağ blokları kesinlikle çakışmamalıdır (Örn: Cluster 1: `10.244.0.0/16`, Cluster 2: `10.245.0.0/16`).
2. **Benzersiz İsim ve ID:** Her kümenin `cluster-name` ve `cluster-id` değerleri benzersiz tanımlanmalıdır.
3. **Ağ Erişimi:** Düğümler arasında tünel protokolleri (VxLAN/Wireguard) için gerekli portların (UDP 8472 vb.) açık olması gerekir.

### ClusterMesh Aktivasyonu (Cilium CLI)

```bash
# 1. Her iki kümede ClusterMesh özelliğini etkinleştirin
cilium clustermesh enable --context aws-cluster --service-type LoadBalancer
cilium clustermesh enable --context onprem-cluster --service-type LoadBalancer

# 2. İki kümeyi birbirine bağlayın (Komşu/Peer yapın)
cilium clustermesh connect --context aws-cluster --destination-context onprem-cluster
```

---

## 3. Global Servisler (Multi-Cluster Load Balancing)

ClusterMesh kurulduktan sonra, bir kümedeki servis başka bir kümedeki podlara trafiği şeffaf olarak dağıtabilir. Buna **Global Service** denir.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ebpf_bgp_ve_clustermesh_manifest_2.yaml](../Manifests/05_networking/ebpf_bgp_ve_clustermesh_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu modelde, AWS'deki bir pod `billing-db-service` adresini çağırdığında, Cilium eBPF sayesinde istek yerel düğümlerdeki veritabanı poduna gider; eğer yerel veritabanı çökmüşse trafik WireGuard tüneli üzerinden On-Premise kümesindeki veritabanı poduna saydam bir şekilde yönlendirilir.

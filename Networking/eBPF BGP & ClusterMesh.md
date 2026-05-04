# eBPF BGP ve Cilium ClusterMesh (Sınırları Kaldırmak)

İleri seviye Kubernetes ağ yönetiminde artık her cluster'ı kapalı bir ada olarak görmek yerine, farklı kıtalardaki (veya farklı Veri Merkezlerindeki/Bulutlardaki) K8s cluster'larını **tek bir büyük Network'te birleştirmek** aranılan bir özelliktir. 

Bunu klasik çözümlerde VPN ve zorlayıcı yönlendirmelerle yaparken, modern ortamda **Cilium ClusterMesh ve BGP (Border Gateway Protocol)** eBPF mimarisiyle natif olarak başarılır.

---

## BGP (Border Gateway Protocol) ve Cilium

Kurumsal veri merkezlerinde K8s ağının (Pod CIDR ve Service CIDR) fiziksel router'lar (Cisco, Juniper) tarafından tanınması için BGP kullanılır. Cilium, eBPF seviyesinde yerleşik BGP desteği sunar — ek yazılım gerekmez.

> [!NOTE]
> Cilium 1.16+ ile **BGP Control Plane v2** API'si (`CiliumBGPClusterConfig`) kullanılmaktadır. Eski `CiliumBGPPeeringPolicy` (v2alpha1) hâlâ desteklenmektedir ancak yeni projeler için v2 API tercih edilmelidir.

### BGP Control Plane v2 (Cilium 1.16+)

```yaml
# CiliumBGPClusterConfig — cluster genelinde BGP yapılandırması
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      rack: rack-1
  bgpInstances:
  - name: instance-65001
    localASN: 65001
    peers:
    - name: core-router
      peerASN: 65000
      peerAddress: 10.0.0.1
      peerConfigRef:
        name: cilium-peer
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  families:
  - afi: ipv4
    safi: unicast
    advertisements:
      matchLabels:
        advertise: bgp
---
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp
spec:
  advertisements:
  - advertisementType: PodCIDR        # Pod IP'lerini router'a anons et
  - advertisementType: Service
    service:
      addresses:
      - ExternalIP
      - LoadBalancerIP
```

Router BGP peering kurulduktan sonra, veri merkezindeki herhangi bir host Pod IP'sine doğrudan ulaşabilir — kube-proxy NAT kuralları veya ek overlay gerekmez.

---

## Cilium ClusterMesh

Bir cluster'ınız Amazon EKS'te (AWS), diğer cluster'ınız On-Prem VMWare sisteminizde. Bu iki kümedeki Servisleri nasıl konuşturursunuz?

ClusterMesh özelliği ile K8s API'leri birbirine değil, **Cilium ajanları birbirine tünel (IPsec/Wireguard) açar**. Yani Ankara'daki K8s Node'u ile Frankfurt'taki K8s Node'u doğrudan iletişim kurar.

### Gereksinimler
1. Her cluster için farklı bir PodCIDR be ServiceCIDR (Çakışma - overlap olmamalıdır).
2. Her cluster'ın benzersiz (Unique) bir isim numarası `cluster-name`, `cluster-id` olmalıdır.
3. Node'lar arası UDP/TCP erişim (Tünel için) açık olmalıdır.

### Kurulum (Cilium CLI)

1. İki cluster için de Mesh'i etkinleştirin:
```bash
# AWS Context
cilium clustermesh enable --context aws-cluster --service-type LoadBalancer

# On-Prem Context
cilium clustermesh enable --context onprem-cluster --service-type LoadBalancer
```

2. İki Cluster'ı "Peer" (Komşu) Yapın:
```bash
cilium clustermesh connect --context aws-cluster --destination-context onprem-cluster
```

---

## Multi-Cluster Global Servis (Ağ Sınırlarını Kaldırma)

Ankara'daki Node'da çalışan bir uygulamanız veritabanına bağlanmak için `mysql-service` çağırdığında, etiketlemeler (Annotations) yardımıyla trafiğin yarısını AWS'deki K8s içinde çalışan diğer `mysql-service` podlarına yük denegelemeyle akıtabilirsiniz!

```yaml
apiVersion: v1
kind: Service
metadata:
  name: global-backend-service
  annotations:
    service.cilium.io/global: "true"   # Olay tamamen bu satırdan ibaret!
spec:
  ports:
  - port: 80
  selector:
    app: backend
```

Cilium, eBPF sayesinde `global-backend-service` IP'sini gördüğü an yükü (Load Balance) tüm dünyada bu etikete ve isme sahip diğer clusterlardaki Pod'lara saydam şekilde (transparent) dağıtır. İşletim sistemi veya kod bundan haberdar bile olmaz, 1 milisaniye gecikmeyle sadece Kernel ağından yönlenir. A+ DevOps!

---

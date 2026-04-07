# eBPF BGP ve Cilium ClusterMesh (Sınırları Kaldırmak)

İleri seviye Kubernetes ağ yönetiminde artık her cluster'ı kapalı bir ada olarak görmek yerine, farklı kıtalardaki (veya farklı Veri Merkezlerindeki/Bulutlardaki) K8s cluster'larını **tek bir büyük Network'te birleştirmek** aranılan bir özelliktir. 

Bunu klasik çözümlerde VPN ve zorlayıcı yönlendirmelerle yaparken, modern ortamda **Cilium ClusterMesh ve BGP (Border Gateway Protocol)** eBPF mimarisiyle natif olarak başarılır.

---

## 3.1 BGP (Border Gateway Protocol) ve Cilium

MetalLB ile L2 ağlarında LoadBalancer elde etmeyi görmüştük. Ancak kurumsal veri merkezlerinde K8s ağının (Pod CIDR ve Service CIDR) fiziksel router'lar (Cisco, Juniper) tarafından tanınması için BGP kullanılır.

Cilium, IPAM ve eBPF seviyesinde `GoBGP` altyapısı barındırır. Herhangi bir ekstra yazılım kurmadan doğrudan Cilium yapılandırmasıyla BGP anonsu yapılabilir.

```yaml
# CiliumBGPPeeringPolicy ile Router'a Peering
apiVersion: "cilium.io/v2alpha1"
kind: CiliumBGPPeeringPolicy
metadata:
  name: rack-1-bgp
spec:
  nodeSelector:
    matchLabels:
      rack: "rack-1"
  virtualRouters:
  - localASN: 65001
    exportPodCIDR: true       # Pod IP'lerini anons et
    neighbors:
    - peerAddress: "10.0.0.1/32"    # Fiziksel Juniper/Cisco Router IP
      peerASN: 65000
```
Artık Veri Merkezi'ndeki bir yetkili, Pod IP'sine ping attığında Router bunu direkt Cilium'a (Worker Node'a) ulaştırır. Kube-proxy iptables NAT kuralları yoktur; her şey WireSpeed ile Kernel üzerinden akar!

---

## 3.2 Cilium ClusterMesh

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

## 3.3 Multi-Cluster Global Servis (Ağ Sınırlarını Kaldırma)

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
*← [Ana Sayfa](../README.md)*

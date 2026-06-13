# Cross-Cluster Networking (Submariner & Cilium ClusterMesh)

Birden fazla Kubernetes cluster'ı arasında pod-to-pod ve service-to-service iletişim sağlamak için kullanılan araçlar.

---

## Problem: Cluster'lar Arası Ağ

```
Cluster A (eu-west-1):   Pod IP 10.244.0.0/16   ClusterIP 10.96.0.0/12
Cluster B (us-east-1):   Pod IP 10.248.0.0/16   ClusterIP 10.100.0.0/12

Sorun: A'daki pod, B'deki servise nasıl ulaşır?
→ Submariner veya Cilium ClusterMesh çözüm sağlar
```

---

## Submariner

CNCF projesi — cluster'lar arası L3 bağlantı sağlar.

```bash
# subctl CLI kurulumu
curl -Ls https://get.submariner.io | bash

# Broker cluster — bağlantı koordinatörü
subctl deploy-broker --kubeconfig=broker.kubeconfig

# Cluster A'yı join et
subctl join broker-info.subm \
  --kubeconfig=cluster-a.kubeconfig \
  --clusterid=cluster-a \
  --natt-port=4500

# Cluster B'yi join et
subctl join broker-info.subm \
  --kubeconfig=cluster-b.kubeconfig \
  --clusterid=cluster-b \
  --natt-port=4500
```

### ServiceExport & ServiceImport

```yaml
# Cluster A'da — servisi dışa aç
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: orders-service
  namespace: production
# → Bu servis Cluster B'den görünür hale gelir
```

```bash
# Cluster B'de otomatik ServiceImport oluşturulur
kubectl get serviceimport -n production --kubeconfig=cluster-b.kubeconfig
# NAME             TYPE           IP                  AGE
# orders-service   ClusterSetIP   [10.100.0.50]       2m

# Cluster B'deki pod artık şunu kullanabilir:
# orders-service.production.svc.clusterset.local
```

---

## Cilium ClusterMesh

Cilium tabanlı cluster'larda yerleşik multi-cluster desteği.

```bash
# Her cluster'da Cilium kurulu olmalı
# Cluster A
cilium clustermesh enable --service-type LoadBalancer --context=cluster-a

# Cluster B
cilium clustermesh enable --service-type LoadBalancer --context=cluster-b

# İki cluster'ı birbirine bağla
cilium clustermesh connect \
  --context=cluster-a \
  --destination-context=cluster-b

# Bağlantıyı doğrula
cilium clustermesh status --context=cluster-a
```

### Global Service (ClusterMesh)

```yaml
# Her iki cluster'a da uygula
apiVersion: v1
kind: Service
metadata:
  name: orders-service
  namespace: production
  annotations:
    service.cilium.io/global: "true"    # Global servis
    service.cilium.io/shared: "true"    # Trafik her iki cluster'a dağıtsın
spec:
  selector:
    app: orders
  ports:
  - port: 80
    targetPort: 8080
```

```
Cluster A (3 pod) + Cluster B (3 pod) → Toplam 6 pod'a yük dağılır
Global load balancing: A'daki istek B'deki pod'a da gidebilir
Failover: A cluster'ı düşerse tüm trafik B'ye geçer
```

---

## Karşılaştırma

| Özellik | Submariner | Cilium ClusterMesh |
|:--------|:-----------|:-------------------|
| CNI bağımlılığı | Bağımsız | **Cilium zorunlu** |
| Kurulum kolaylığı | Orta | Kolay (Cilium varsa) |
| Performans | IPsec/WireGuard tunnel | eBPF — **doğrudan** |
| Global LB | ServiceImport | **Global Service** |
| Failover | Manuel | **Otomatik** |
| Encryption | IPsec/WireGuard | WireGuard |

---

## Global Service Failover Senaryosu

```yaml
# Cluster A öncelikli, B yedek
apiVersion: v1
kind: Service
metadata:
  name: api-service
  annotations:
    service.cilium.io/global: "true"
    service.cilium.io/affinity: local   # Önce local cluster'a git
spec:
  selector:
    app: api
  ports:
  - port: 80
```

```
Normal:     İstek → Cluster A pod'ları (local affinity)
Hata:       Cluster A pod'ları yok → Cluster B pod'larına otomatik failover
Geri dön:  Cluster A pod'ları tekrar hazır → local affinity devreye girer
```

---

## DNS Federasyonu

```yaml
# CoreDNS yapılandırması — cross-cluster DNS
# cluster-a'daki pod, cluster-b'deki servise erişmek için:
# orders-service.production.svc.cluster-b.local

# CoreDNS Corefile:
cluster-b.local:53 {
    forward . <cluster-b-coredns-ip>:53
    cache 30
}
```

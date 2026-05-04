# Cluster Federation — Liqo & Submariner

Birden fazla Kubernetes cluster'ını tek bir mantıksal küme gibi yönetmek, iş yüklerini cluster'lar arasında taşımak ve ağları birleştirmek için kullanılan federasyon katmanı.

---

## Ne Zaman Federasyon Gerekir?

```
Multi-Cluster ≠ Federation

Multi-Cluster:   Her cluster bağımsız, GitOps ile senkronize
Federation:      Cluster'lar birbirini "görür", workload taşınabilir

Kullanım senaryoları:
  ✅ Disaster Recovery — ana cluster çökünce standby'a otomatik geç
  ✅ Burst-to-cloud — on-prem dolunca cloud'a taş
  ✅ Data locality — kullanıcıya en yakın cluster'da çalış
  ✅ Dev/Test workload dağıtımı
```

---

## Liqo — Kubernetes-Native Federasyon

Liqo, cluster'lar arasında şeffaf workload paylaşımı sağlar. Pod'lar sanki local çalışıyormuş gibi remote cluster'da çalışır.

### Kurulum

```bash
# liqoctl CLI kurulumu
curl -fsSL https://github.com/liqotech/liqo/releases/latest/download/liqoctl-linux-amd64.tar.gz | tar xzf -
install -m 0755 liqoctl /usr/local/bin/liqoctl

# Cluster'a Liqo kur (kubeadm cluster)
liqoctl install kubeadm \
  --cluster-name cluster-a \
  --pod-cidr 10.244.0.0/16 \
  --service-cidr 10.96.0.0/12

# AKS için
liqoctl install aks \
  --cluster-name aks-west \
  --resource-group myRG \
  --resource-name myAKS

# EKS için
liqoctl install eks \
  --cluster-name eks-eu \
  --region eu-west-1
```

### Cluster Peering

```bash
# İki cluster'ı birbirine bağla
# cluster-a'dan cluster-b'ye yönlendirme
export KUBECONFIG=cluster-a.yaml
liqoctl peer out-of-band cluster-b \
  --kubeconfig cluster-b.yaml

# Peering durumunu kontrol et
liqoctl status peer
kubectl get foreignclusters

# Örnek çıktı:
# NAME        OUTGOING     INCOMING    AGE
# cluster-b   Established  Established 5m
```

### Workload Offloading

```bash
# Namespace'i uzak cluster'a offload et
liqoctl offload namespace production \
  --namespace-mapping-strategy EnforceSameName \
  --pod-offloading-strategy LocalAndRemote    # Hem local hem remote

# Sadece remote'da çalıştır
liqoctl offload namespace production \
  --pod-offloading-strategy Remote

# Offloading durumu
kubectl get namespaceoffloading production
```

```yaml
# Liqo VirtualNode — remote cluster'ı local node gibi görür
apiVersion: v1
kind: Pod
metadata:
  name: remote-workload
  namespace: production
spec:
  # Liqo otomatik olarak remote'a schedule eder
  # Node affinity ile yönlendirebilirsiniz:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: liqo.io/remote-cluster-id
            operator: In
            values:
            - cluster-b-id
  containers:
  - name: app
    image: nginx:1.27
```

---

## Submariner — Cross-Cluster Ağ

Submariner, farklı cluster'lar arasında overlay ağ kurarak pod ve service IP'lerinin birbirini görmesini sağlar.

### Kurulum

```bash
# subctl CLI
curl -Ls https://get.submariner.io | bash
export PATH=$PATH:~/.local/bin

# Broker cluster (network metadata için)
subctl deploy-broker --kubeconfig broker.yaml

# Cluster'ları broker'a bağla
subctl join broker-info.subm \
  --kubeconfig cluster-a.yaml \
  --clusterid cluster-a \
  --cable-driver libreswan    # veya vxlan, wireguard

subctl join broker-info.subm \
  --kubeconfig cluster-b.yaml \
  --clusterid cluster-b \
  --cable-driver libreswan

# Bağlantıyı doğrula
subctl show connections
subctl diagnose all
```

### ServiceExport — Service'i Federasyona Aç

```yaml
# cluster-a'da: backend service'i federasyona export et
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: backend
  namespace: production

---
# cluster-b'de: ServiceImport otomatik oluşur
# backend.production.svc.clusterset.local → cluster-a'daki backend'e gider
```

```bash
# ServiceImport görüntüle (cluster-b'de)
kubectl get serviceimport -n production

# Cross-cluster DNS testi
kubectl run test --image=busybox --rm -it --restart=Never \
  -- nslookup backend.production.svc.clusterset.local
```

---

## KubeFed v2 (Kubernetes Cluster Federation)

> [!WARNING]
> KubeFed v2 2024 sonunda **archived** edildi. Yerini Liqo, Karmada ve Submariner kombinasyonu aldı. Yeni projeler için Liqo + Submariner kombinasyonu önerilir.

---

## Liqo vs Karmada vs Submariner

| Özellik | Liqo | Karmada | Submariner |
|:--------|:----:|:-------:|:----------:|
| **Workload offloading** | ✅ Şeffaf | ✅ Policy | ❌ |
| **Cross-cluster service** | ✅ | ✅ | ✅ |
| **Cross-cluster pod IP** | ✅ | ❌ | ✅ |
| **Karmaşıklık** | Orta | Yüksek | Orta |
| **CNCF projesi** | Sandbox | Sandbox | Sandbox |
| **En iyi kullanım** | Şeffaf offloading | Policy tabanlı dağıtım | Ağ birleşimi |

---

## Tipik Federasyon Mimarisi

```
                    [GitOps/ArgoCD — Hub]
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   [Cluster-EU-West]  [Cluster-US-East]  [Cluster-Cloud-Burst]
          │                │                │
     Liqo Peer ←── Submariner ──→ Liqo Peer
          │                │                │
   [ServiceExport]  [ServiceExport]  [ServiceImport]
          └──── clusterset.local DNS ────────┘
```

```bash
# Federasyon sağlık kontrolü
liqotech/liqo: kubectl get foreignclusters
submariner: subctl show all
karmada: kubectl get clusters --context karmada-host
```

> [!TIP]
> Başlangıç için Submariner (sadece ağ) veya Liqo (ağ + workload) tercih edin. Karmada daha fazla operasyonel karmaşıklık getirir ama policy tabanlı dağıtım için güçlüdür.

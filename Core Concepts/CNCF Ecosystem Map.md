# CNCF Ekosistemi Haritası

Cloud Native Computing Foundation (CNCF), Kubernetes etrafındaki 1000+ projeyi barındırır. "Hangi kategoride hangi araç, ne işe yarıyor?" sorusunun cevabı.

---

## Olgunluk Seviyeleri

```
Graduated (Mezun)   → Production-ready, büyük ölçekte kanıtlanmış
Incubating (Kuluçka) → Aktif geliştirme, production kullanımı artan
Sandbox (Kum havuzu) → Erken aşama, deneysel
```

---

## 1. Orkestrasyon

| Araç | Durum | Açıklama |
|:-----|:------|:---------|
| **Kubernetes** | Graduated | Container orkestrasyon standardı |
| **Crossplane** | Graduated | Kubernetes ile cloud altyapı yönetimi |

---

## 2. Container Runtime

| Araç | Durum | Açıklama |
|:-----|:------|:---------|
| **containerd** | Graduated | K8s varsayılan runtime |
| **CRI-O** | Graduated | OCI uyumlu hafif runtime (OpenShift) |
| **gVisor** | Sandbox | Google'ın user-space kernel'i (güvenli sandbox) |
| **Kata Containers** | — | VM tabanlı güvenli container runtime |

---

## 3. Networking & Service Mesh

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Cilium** | Graduated | eBPF tabanlı CNI, kube-proxy yerine, 2026 standardı |
| **Calico** | — | Geleneksel CNI, BGP desteği |
| **Flannel** | — | Basit CNI, küçük cluster'lar |
| **Istio** | Graduated | Production service mesh, mTLS, traffic management |
| **Linkerd** | Graduated | Hafif, basit service mesh, Rust tabanlı |
| **Envoy** | Graduated | L7 proxy, Istio/Consul altyapısı |
| **CoreDNS** | Graduated | K8s varsayılan DNS |
| **MetalLB** | — | Bare-metal LoadBalancer |

```
CNI Seçimi:
  Küçük cluster → Flannel
  Production, BGP → Calico
  eBPF, güvenlik, performans → Cilium (2026 önerisi)
  
Service Mesh Seçimi:
  Tam özellik, enterprise → Istio
  Sadelik, düşük overhead → Linkerd
  eBPF tabanlı (Istio'suz) → Cilium Service Mesh
```

---

## 4. Storage

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Rook** | Graduated | Ceph'i K8s üzerinde orkestre eder |
| **Longhorn** | Graduated | Rancher'ın dağıtık block storage'ı |
| **OpenEBS** | Graduated | Mayastor ile yüksek performans |
| **Velero** | — | Backup & restore |
| **external-snapshotter** | — | CSI volume snapshot standardı |

---

## 5. Observability

| Araç | Durum | Rol |
|:-----|:------|:----|
| **Prometheus** | Graduated | Metrik toplama & alerting |
| **Grafana** | — | Görselleştirme (Loki, Tempo entegrasyonu) |
| **Jaeger** | Graduated | Distributed tracing (Tempo'nun öncülü) |
| **OpenTelemetry** | Graduated | Observability standardı (metrik+log+trace) |
| **Thanos** | Incubating | Uzun süreli Prometheus depolama |
| **Cortex** | Graduated | Çok tenant Prometheus |
| **Fluentd** | Graduated | Log toplama pipeline |
| **Fluent Bit** | Graduated | Hafif log toplayıcı (Fluentd'nin yerine geçiyor) |

```
2026 Stack (LGTM):
  Loki (log) + Grafana (UI) + Tempo (trace) + Mimir (Prometheus uzun dönem)
```

---

## 6. Security

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Falco** | Graduated | Runtime security, davranış analizi |
| **OPA / Gatekeeper** | Graduated | Policy as code |
| **Kyverno** | Incubating | K8s-native policy engine |
| **cert-manager** | — | TLS sertifika yönetimi |
| **SPIFFE/SPIRE** | Graduated | Workload identity, zero-trust |
| **Notary / Notation** | Incubating | Container image imzalama |
| **Sigstore / Cosign** | — | Supply chain güvenliği |
| **Trivy** | — | Image & config vulnerability scanner |

---

## 7. GitOps & CI/CD

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Argo CD** | Graduated | UI odaklı GitOps |
| **Flux** | Graduated | Multi-tenant, Git-native GitOps |
| **Argo Workflows** | — | K8s üzerinde iş akışı motoru |
| **Tekton** | — | Cloud-native CI/CD pipeline |
| **Helm** | Graduated | K8s paket yöneticisi |
| **Kustomize** | — | YAML overlay aracı |

```
GitOps Seçimi:
  UI + Dashboard → ArgoCD
  Multi-tenant, kod odaklı → Flux
  Her ikisi → Birlikte kullanılabilir (farklı roller)
```

---

## 8. Autoscaling

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **KEDA** | Graduated | Event-driven autoscaling |
| **Karpenter** | — | AWS/Azure node provisioning |
| **Cluster Autoscaler** | — | Cloud-agnostic node scaling |
| **VPA** | — | Dikey pod ölçekleme |
| **HPA** | Kubernetes built-in | Yatay pod ölçekleme |

---

## 9. Platform Engineering

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Backstage** | Incubating | Developer portal, IDP |
| **Crossplane** | Graduated | Cloud kaynakları K8s CRD olarak |
| **Kratix** | Sandbox | Promise-based platform |
| **vCluster** | — | Sanal K8s cluster |
| **Kubecost** | — | Maliyet analizi |

---

## 10. AI & Machine Learning

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Kubeflow** | — | End-to-end ML platform |
| **Ray** | — | Dağıtık hesaplama, RL, LLM training |
| **KServe** | — | Model serving (multi-framework) |
| **Volcano** | Incubating | Batch/ML iş yükü scheduler |
| **NVIDIA GPU Operator** | — | GPU node yönetimi |

---

## 11. Multi-Cluster

| Araç | Durum | Ne Zaman? |
|:-----|:------|:---------|
| **Cluster API** | Incubating | Declarative cluster lifecycle |
| **Karmada** | Incubating | Multi-cluster policy & federation |
| **OCM (Open Cluster Mgmt)** | Sandbox | Red Hat'in multi-cluster çözümü |
| **Submariner** | Sandbox | Cluster arası ağ |
| **Liqo** | — | Dynamic resource sharing |

---

## 12. Managed Kubernetes (Cloud)

| Platform | Provider | Özellik |
|:---------|:---------|:--------|
| **EKS** | AWS | Fargate, IRSA, Karpenter native |
| **GKE** | Google | Autopilot, Workload Identity, en olgun |
| **AKS** | Azure | AAD entegrasyonu, Arc |
| **DOKS** | DigitalOcean | Basit, geliştirici dostu |
| **OKE** | Oracle | ARM instance desteği |

---

## Araç Seçim Kılavuzu (2026)

```
Yeni cluster kuracaksın:
  OS        → Ubuntu 22.04 veya Talos Linux (immutable)
  Kurulum   → kubeadm (bare-metal) | EKS/GKE/AKS (cloud)
  CNI       → Cilium
  Ingress   → NGINX Ingress Controller veya Gateway API
  GitOps    → ArgoCD veya Flux
  Monitoring → Prometheus + Grafana + Loki + Tempo
  Security  → Falco + Kyverno + cert-manager
  Backup    → Velero

Kaçın:
  ❌ kube-proxy (Cilium ile değiştir)
  ❌ Flannel (production için yetersiz)
  ❌ Docker runtime (containerd/CRI-O kullan)
  ❌ Helm'siz manifest deploy (her zaman Helm veya Kustomize)
```

---

## CNCF Proje Durumu Takibi

```bash
# Güncel CNCF landscape
https://landscape.cncf.io

# Graduated projeler
https://www.cncf.io/projects/

# Proje olgunluk kriterleri
https://github.com/cncf/toc/blob/main/process/graduation_criteria.md
```

> [!TIP]
> CNCF landscape 1000+ araç içerir. **Hepsini öğrenmek mümkün değil.** Önce kategorileri öğren, her kategoride 1-2 araçta derin ol. Kubernetes ekosistemi bu kitaptaki 15 bölüm yapısını tam olarak yansıtıyor.

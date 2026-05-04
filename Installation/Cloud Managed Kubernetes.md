# Cloud Managed Kubernetes

EKS (AWS), GKE (Google) ve AKS (Azure), Kubernetes control plane'ini yöneten managed hizmetlerdir. Worker node'ların yönetimi de dahil olmak üzere birçok operasyonel sorumluluğu bulut sağlayıcıya devretmenizi sağlar.

---

## Platform Karşılaştırması (2026)

| Özellik | EKS (AWS) | GKE (Google) | AKS (Azure) |
|:--------|:----------|:-------------|:------------|
| **En güçlü yön** | AWS ekosistemi | Kubernetes olgunluğu | Azure AD entegrasyonu |
| **Autopilot/Serverless** | Fargate | Autopilot | — |
| **Node ölçekleme** | Karpenter | Node Auto Provisioning | Cluster Autoscaler |
| **Workload Identity** | IRSA | Workload Identity | Azure Workload Identity |
| **Ağ** | AWS VPC CNI | Dataplane V2 (eBPF) | Azure CNI / Cilium |
| **Ücretsiz Control Plane** | ❌ ($0.10/saat) | ✅ (Autopilot hariç) | ✅ |
| **K8s güncelliği** | Orta | Hızlı | Orta |

---

## EKS (Amazon Elastic Kubernetes Service)

### Cluster Oluşturma

```bash
# eksctl ile (önerilen)
eksctl create cluster \
  --name production \
  --region eu-west-1 \
  --version 1.31 \
  --nodegroup-name workers \
  --node-type m6g.xlarge \         # Graviton (ARM, daha ucuz)
  --nodes-min 2 \
  --nodes-max 10 \
  --managed \                       # Managed node group
  --with-oidc \                     # IRSA için
  --alb-ingress-access

# Terraform ile
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "production"
  cluster_version = "1.31"

  eks_managed_node_groups = {
    workers = {
      instance_types = ["m6g.xlarge"]
      min_size       = 2
      max_size       = 10
    }
  }
  enable_irsa = true
}
```

### IRSA — Pod'a AWS Yetki

```bash
# OIDC provider oluştur
eksctl utils associate-iam-oidc-provider \
  --cluster production --approve

# ServiceAccount için IAM role bağla
eksctl create iamserviceaccount \
  --name s3-reader \
  --namespace production \
  --cluster production \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve \
  --override-existing-serviceaccounts
```

```yaml
# Pod'da IRSA ServiceAccount kullan
spec:
  serviceAccountName: s3-reader    # AWS role otomatik mount edilir
```

### Karpenter ile Node Ölçekleme

```bash
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace kube-system \
  --set settings.clusterName=production \
  --set settings.interruptionQueue=production-karpenter
```

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: [c, m, r]
      - key: kubernetes.io/arch
        operator: In
        values: [amd64, arm64]
      - key: karpenter.sh/capacity-type
        operator: In
        values: [spot, on-demand]
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
```

---

## GKE (Google Kubernetes Engine)

### Cluster Oluşturma

```bash
# Standard cluster
gcloud container clusters create production \
  --region europe-west1 \
  --cluster-version 1.31 \
  --machine-type n2d-standard-4 \
  --num-nodes 2 \
  --enable-autoscaling \
  --min-nodes 1 --max-nodes 10 \
  --workload-pool=my-project.svc.id.goog \    # Workload Identity
  --enable-ip-alias \
  --enable-network-policy \
  --dataplane-v2                               # eBPF (Cilium tabanlı)

# Autopilot (fully managed node)
gcloud container clusters create-auto production \
  --region europe-west1
```

### Workload Identity

```bash
# GCP ServiceAccount ile K8s ServiceAccount bağla
gcloud iam service-accounts add-iam-policy-binding \
  gsa@my-project.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:my-project.svc.id.goog[production/app-sa]"
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: production
  annotations:
    iam.gke.io/gcp-service-account: gsa@my-project.iam.gserviceaccount.com
```

---

## AKS (Azure Kubernetes Service)

### Cluster Oluşturma

```bash
# Resource group
az group create --name rg-production --location westeurope

# AKS cluster
az aks create \
  --resource-group rg-production \
  --name production \
  --kubernetes-version 1.31 \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --enable-managed-identity \
  --enable-workload-identity \         # Azure Workload Identity
  --enable-oidc-issuer \
  --network-plugin azure \
  --network-policy cilium \            # Cilium CNI
  --enable-cluster-autoscaler \
  --min-count 2 --max-count 10

# kubeconfig al
az aks get-credentials --resource-group rg-production --name production
```

### Azure Workload Identity

```bash
# Managed Identity oluştur
az identity create --name app-identity --resource-group rg-production

# Federated credential ekle
az identity federated-credential create \
  --name app-federated \
  --identity-name app-identity \
  --resource-group rg-production \
  --issuer $(az aks show --name production --resource-group rg-production \
    --query "oidcIssuerProfile.issuerUrl" -o tsv) \
  --subject "system:serviceaccount:production:app-sa"
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: production
  annotations:
    azure.workload.identity/client-id: "<MANAGED_IDENTITY_CLIENT_ID>"
```

---

## Ortak Best Practices

```bash
# Private cluster (control plane'e public erişim yok)
# EKS: --endpoint-private-access=true --endpoint-public-access=false
# GKE: --enable-private-cluster --master-ipv4-cidr 172.16.0.0/28
# AKS: --enable-private-cluster

# Node imajını güncel tut
# EKS: Managed node group auto-update
aws eks update-nodegroup-version --cluster-name prod --nodegroup-name workers

# GKE: Auto-upgrade
gcloud container node-pools update default-pool \
  --cluster production \
  --enable-autoupgrade

# AKS: Upgrade channel
az aks update --name production --resource-group rg-production \
  --auto-upgrade-channel stable
```

> [!TIP]
> **Maliyet optimizasyonu:** EKS'de Graviton (ARM) node'lar amd64'e göre ~%40 ucuz. GKE Autopilot sadece kullandığın kadar ödersin. Her üçünde de Spot/Preemptible node'ları Karpenter/Node Auto Provisioner ile yönet.

> [!IMPORTANT]
> Managed cluster = Control plane yönetiminden kurtulursun, ama **node OS patch, add-on versiyonları, networking** senin sorumluluğunda. "Managed" sihirli bir kelime değil.

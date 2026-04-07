# Bulut Tabanlı Kubernetes (GKE ve EKS)

Üretim ortamlarında kendi cluster'ınızı (Self-managed) kurmak yerine bulut sağlayıcıların (Cloud Managed) sunduğu hizmetleri kullanmak operasyonel yükü azaltır.

---

## 8.1 Google Kubernetes Engine (GKE)

GCP tarafından yönetilen Kubernetes servisidir. En gelişmiş "Autopilot" ve "Standard" modları bulunur.

### Temel Operasyonlar (gcloud):
```bash
# Cluster bilgilerini al
gcloud container clusters list

# Kubeconfig'i yapılandır (Hizmete bağlanma)
gcloud container clusters get-credentials <CLUSTER_NAME> \
    --region <REGION> --project <PROJECT_ID>

# Örnek: Bir Flask uygulamasını LoadBalancer ile yayınlama:
kubectl apply -f https://raw.githubusercontent.com/.../gke-flask-demo.yaml
```

### GKE'ye Özgü Avantajlar:
1.  **Workload Identity:** Pod'ların ServiceAccount'larını GCP IAM rolleriyle doğrudan eşleştirme.
2.  **Binary Authorization:** Sadece imzalanmış imajların çalışmasını sağlama.

---

## 8.2 Amazon Elastic Kubernetes Service (EKS)

AWS tarafından yönetilen Kubernetes servisidir. Worker node'lar EC2 veya Fargate (Serverless) üzerinden yönetilebilir.

### Kurulum ve Yönetim (eksctl):
```bash
# Cluster oluşturma (Önerilen yöntem)
eksctl create cluster \
  --name my-eks-cluster \
  --region us-west-2 \
  --nodegroup-name standard-nodes \
  --node-type t3.medium \
  --nodes 3

# Bulut LoadBalancer Entegrasyonu:
# Servis tipini LoadBalancer yaptığınızda AWS anında bir ELB (veya NLB) oluşturur.
```

---

## 8.3 Bulut Entegrasyonunda Dikkat Edilecekler

| Özellik | GKE | EKS |
|:---|:---|:---|
| **Auth** | Gcloud IAM | AWS IAM (IRSA) |
| **Ağ (CNI)** | GCP VPC Native | AWS VPC CNI |
| **Ölçekleme** | Cluster Autoscaler | Cluster Autoscaler / Karpenter |
| **Disk (CSI)** | GCE Persistent Disk | AWS EBS / EFS |

---

## 8.4 Ölçeklenebilirlik (Autoscaling)

Bulut ortamlarının en büyük avantajı, node sayısının trafiğe göre otomatik değişmesidir:
1.  **HPA (Horizontal Pod Autoscaler):** Pod sayısını artırır.
2.  **VPA (Vertical Pod Autoscaler):** Pod kaynak limitlerini (CPU/RAM) ayarlar.
3.  **CA (Cluster Autoscaler):** Pod'lar yer bulamadığında yeni fiziksel Node ekler.

---
*← [Ana Sayfa](../README.md)*

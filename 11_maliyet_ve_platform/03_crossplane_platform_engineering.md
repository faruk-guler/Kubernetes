# Crossplane ve Platform Mühendisliği (IDP)

Terraform gibi geleneksel "Infrastructure as Code" (IaC) araçları güçlüdür, ancak "Drift" (manuel yapılan değişikliklerin koddan sapması) problemi taşırlar. **Crossplane**, Kubernetes'in Controller (Kube-Controller-Manager) mantığını kullanarak AWS, GCP ve Azure kaynaklarını YAML ile otomaktik olarak uzlaştırır (Reconciliation). Kubernetes artık sadece konteyner yönetmez, "Cloud Control Plane" olur.

---

## 3.1 Crossplane Temel Mantığı

1. **Provider:** AWS, Azure gibi bulut sağlayıcıların K8s diline (CRD) entegre edilmesi.
2. **Managed Resource:** Tek bir parça bulut servisi (Örn: `Bucket`, `RDSInstance`).
3. **Composite Resource Definition (XRD):** Geliştiriciler için sizin belirlediğiniz bir şablon (Örn: `XPostgreSQLInstance`).

Geliştiricilere (Developers) sadece basit bir YAML verilir. Onlar karmaşık AWS vpc/subnet mimarisini bilmek zorunda kalmaz.

---

## 3.2 Kurulum ve AWS Provider

```bash
# Helm ile Crossplane kurulumu
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm upgrade --install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system \
    --create-namespace

# AWS Provider yükleme
kubectl crossplane install provider xpkg.upbound.io/upbound/provider-aws:v0.40.0
```

---

## 3.3 Bulut Kaynağı Oluşturma Örneği

Artık Kubernetes'e sadece bir `Bucket` (S3) manifesti uyguladığımızda, Crossplane AWS'ye gidip bunu oluşturacak ve konfigürasyon sapması (drift) olursa her döngüde düzeltecektir.

```yaml
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: crossplane-s3-test-12345
spec:
  forProvider:
    region: eu-central-1
  providerConfigRef:
    name: default
```

```bash
# Kaynağın gelip gelmediğini K8s üzerinden kontrol edin:
kubectl get bucket

NAME                       READY   SYNCED   AGE
crossplane-s3-test-12345   True    True     2m
```

---

## 3.4 Platform Mühendisliği ve "Self-Service"

Platform takımları (Platform Engineers), Backstage (Bkz. 11.2) ve Crossplane'i birleştirir.
Bir yazılımcı Backstage portalından "Bana Veritabanı Ver" tuşuna basar. Backstage arkadan K8s'e Crossplane nesnesini gönderir. Ve yazılımcıya anında bir Endpoint ve şifre Secret'i iade edilir. 

> [!TIP]
> **GitOps Entegrasyonu**
> Crossplane dosyalarınız (AWS VPC'leri vb.) Git'te durur. ArgoCD (Bkz. Bölüm 4) Git'ten bunları alır, K8s'e basar, Crossplane ise K8s'ten alıp AWS'yi oluşturur. Kusursuz Kapalı Döngü!

---
*← [Backstage & IDP](02_backstage_idp.md) | [Ana Sayfa](../README.md)*

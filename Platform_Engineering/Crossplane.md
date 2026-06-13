# Crossplane — Kubernetes ile Bulut Altyapı Yönetimi

Terraform gibi geleneksel "Infrastructure as Code" (IaC) araçları güçlüdür, ancak "Drift" (manuel yapılan değişikliklerin koddan sapması) problemi taşırlar. **Crossplane**, Kubernetes'in Controller mantığını kullanarak AWS, GCP ve Azure kaynaklarını YAML ile otomatik olarak uzlaştırır (Reconciliation). Kubernetes artık sadece konteyner yönetmez — "Cloud Control Plane" haline gelir.

---

## Crossplane Temel Mantığı

1. **Provider:** AWS, Azure gibi bulut sağlayıcıların K8s diline (CRD) entegre edilmesi.
2. **Managed Resource:** Tek bir parça bulut servisi (örn: `Bucket`, `RDSInstance`).
3. **Composite Resource Definition (XRD):** Geliştiriciler için platform ekibinin belirlediği şablon (örn: `XPostgreSQLInstance`).

Geliştiricilere (Developers) sadece basit bir YAML verilir. Onlar karmaşık AWS VPC/subnet mimarisini bilmek zorunda kalmaz.

---

## Kurulum ve AWS Provider

```bash
# Helm ile Crossplane kurulumu
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version 1.17.1

# AWS Provider yükleme (Upbound Universal Crossplane)
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-s3
spec:
  package: xpkg.upbound.io/upbound/provider-aws-s3:v1.14.0
EOF
```

---

## AWS Kimlik Doğrulama (IRSA / Workload Identity)

```yaml
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: IRSA    # EKS üzerinde IRSA (IAM Roles for Service Accounts)
```

---

## Bulut Kaynağı Oluşturma Örneği

Kubernetes'e sadece bir `Bucket` (S3) manifesti uygulandığında, Crossplane AWS'ye gidip bunu oluşturur ve konfigürasyon sapması (drift) olursa her döngüde düzeltir:

```yaml
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: my-app-assets-prod
spec:
  forProvider:
    region: eu-central-1
    tags:
      Environment: production
      ManagedBy: crossplane
  providerConfigRef:
    name: default
```

```bash
# Kaynağın oluşturulup oluşturulmadığını kontrol et
kubectl get bucket my-app-assets-prod
# NAME                   READY   SYNCED   AGE
# my-app-assets-prod     True    True     2m
```

---

## Composite Resource — Self-Service Platform

Platform ekipleri, geliştiriciler için basit soyutlamalar tanımlar:

```yaml
# XRD — geliştiriciye sunulan API
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xpostgresqlinstances.platform.example.com
spec:
  group: platform.example.com
  names:
    kind: XPostgreSQLInstance
  versions:
  - name: v1alpha1
    schema:
      openAPIV3Schema:
        properties:
          spec:
            properties:
              parameters:
                properties:
                  storageGB:
                    type: integer
                    default: 20
```

```yaml
# Geliştirici sadece bunu yazar — AWS RDS detaylarını bilmez
apiVersion: platform.example.com/v1alpha1
kind: XPostgreSQLInstance
metadata:
  name: my-app-db
spec:
  parameters:
    storageGB: 100
  compositionRef:
    name: postgresql-aws
```

---

## GitOps Entegrasyonu

Crossplane manifestleri Git'te durur. ArgoCD Git'ten alır, K8s'e basar, Crossplane ise K8s'ten alıp AWS'yi oluşturur — kapalı döngü:

```
Git Repo ─→ ArgoCD ─→ K8s API ─→ Crossplane ─→ AWS/GCP/Azure
              ↑                        │
              └──── Reconcile ─────────┘
```

> [!TIP]
> Crossplane + Backstage kombinasyonu ile geliştiriciler Backstage portalından "Bana Veritabanı Ver" düğmesine basar; Backstage arka planda K8s'e Crossplane nesnesi gönderir ve geliştiriciye otomatik olarak bir endpoint ve Secret iade edilir.

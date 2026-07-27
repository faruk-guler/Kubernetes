# Crossplane ile Kubernetes Kontrol Düzlemi (Cloud Control Plane) ve Bulut Altyapı Yönetimi

Bulut altyapılarını yönetmek için geleneksel olarak kullanılan **Terraform** ve benzeri Infrastructure as Code (IaC) araçları güçlü olmalarına rağmen, manuel müdahalelerin kodu bozması (**State Drift**) ve CI/CD süreçlerinin karmaşıklığı gibi dezavantajlara sahiptir.

**Crossplane**, Kubernetes'in yerleşik denetleyici (controller) ve uzlaştırma (reconciliation loop) mekanizmasını kullanarak AWS, Azure ve GCP gibi bulut sağlayıcılarının kaynaklarını doğrudan Kubernetes YAML dosyaları ile yönetmenizi sağlayan açık kaynaklı bir CNCF projesidir. Crossplane ile Kubernetes sadece konteynerleri değil, tüm bulut altyapısını yöneten merkezi bir **Bulut Kontrol Düzlemi (Cloud Control Plane)** haline gelir.

---

## 1. Crossplane Temel Bileşenleri

* **Provider (Sağlayıcı):** İlgili bulut sağlayıcısının (AWS, GCP, Azure) API kaynaklarını Kubernetes CRD nesneleri olarak kümeye yükleyen pakettir.
* **Managed Resource (Yönetilen Kaynak - MR):** Bulut sağlayıcısına ait tekil bir altyapı kaynağının Kubernetes üzerindeki temsilidir (Örn: `Bucket`, `RDSInstance`, `Subnet`).
* **Composite Resource Definition (XRD):** Platform ekibinin, geliştiriciler için oluşturduğu özel ve basitleştirilmiş altyapı şablonlarının arayüz tanımıdır.
* **Composition (Bileşim):** Bir XRD çağrıldığında arka planda hangi gerçek Managed Resource nesnelerinin (Örn: DB Instance + Subnet Group + Security Group) oluşturulacağını tanımlayan reçetedir.

---

## 2. Kurulum ve Provider Yükleme

Crossplane denetleyicisini kurmak ve AWS S3 sağlayıcısını aktif etmek için:

```bash
# 1. Helm ile Crossplane Kurulumu
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version 1.17.1

# 2. AWS S3 Provider Tanımı
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

## 3. AWS Kimlik Doğrulama Yapılandırması (IRSA / IAM OIDC)

AWS üzerindeki kaynakları oluşturabilmek için Crossplane podlarına IAM rolü yetkisi (IRSA) atanmalıdır.

### `ProviderConfig` ve Controller Rol Eşleştirmesi

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [crossplane_manifest_2.yaml](../Manifests/10_platform/crossplane_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Managed Resource ile AWS S3 Bucket Oluşturma

Provider kurulup yetkilendirildikten sonra, aşağıdaki YAML dosyasını kümeye uyguladığınızda Crossplane otomatik olarak AWS üzerinde gerçek bir S3 Bucket oluşturur.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [crossplane_manifest_3.yaml](../Manifests/10_platform/crossplane_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Eğer bir kullanıcı AWS konsoluna girip bu S3 bucket'ı manuel silerse veya ayarlarını değiştirirse, Crossplane dakikalar içinde durumu fark eder (**Drift Detection**) ve ayarları eski haline getirir (Self-Healing).

---

## 5. Composite Resources (XRD & Composition) ile Platform Soyutlama

Geliştiricilerin AWS veritabanı kurmak için karmaşık ağ kurallarını, VPC ayarlarını bilmelerine gerek yoktur. Platform ekibi bir şablon sunar ve geliştirici bunu kullanır.

### A. CompositeResourceDefinition (XRD - Arayüz Tanımı)

Geliştiricilerin dolduracağı parametre alanlarını tanımlayan şablon:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [crossplane_manifest_1.yaml](../Manifests/10_platform/crossplane_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Composition (Arka Plandaki Reçete)

Yukarıdaki şablon çağrıldığında arka planda AWS RDS veritabanı, subnet ve security group'u nasıl oluşturacağını tanımlayan dosya:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [crossplane_manifest_4.yaml](../Manifests/10_platform/crossplane_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### Geliştiricinin Kullanımı (Veritabanı Talebi - Claim)

Artık geliştirici kendi namespace'inde sadece şu basit dosyayı uygulayarak güvenli bir veritabanı elde edebilir. Bağlantı şifreleri otomatik olarak namespace'e `k8s-db-secret` adıyla döner:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [crossplane_manifest_5.yaml](../Manifests/10_platform/crossplane_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. GitOps + Crossplane Kapalı Döngü Entegrasyonu

Crossplane manifestoları Git reposunda saklanır. ArgoCD bu dosyaları Git'ten okuyarak Kubernetes API'sine yazar. Kubernetes API'sini dinleyen Crossplane ise AWS/GCP üzerinde kaynakları oluşturur. Tüm altyapı GitOps üzerinden kontrol edilmiş olur.

```
[ Git Repo ] ──► [ ArgoCD ] ──► [ Kubernetes API ] ──► [ Crossplane ] ──► [ AWS / GCP Cloud ]
```

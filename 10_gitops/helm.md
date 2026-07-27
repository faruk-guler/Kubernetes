# Helm ile Kubernetes Paket Yönetimi (Helm Guide)

Kubernetes üzerinde mikroservis tabanlı uygulamaları çalıştırmak; Pod, Deployment, Service, Ingress, PersistentVolumeClaim ve Secret gibi düzinelerce farklı kaynağın tek tek oluşturulmasını gerektirir. Her bir servis için elle ayrı YAML dosyaları yazmak ve bunları yönetmek zamanla ciddi bir operasyonel karmaşıklığa (**YAML cehennemi**) dönüşür.

**Helm**, bu karmaşık kaynak setlerini tek bir paket halinde bir araya getiren, sürümleyen ve yöneten Kubernetes'in resmi paket yöneticisidir. Uygulamaları "Chart" adı verilen standart paketler haline getirerek dağıtımı kolaylaştırır.

---

## 1. Helm Nedir?

Helm, Kubernetes için Linux dünyasındaki `apt` veya `yum` benzeri bir paket yöneticisidir. Helm kullanarak, önceden paketlenmiş karmaşık uygulamaları (Prometheus, ArgoCD, Kafka vb.) tek bir komutla kurabilir, güncelleyebilir veya geri alabilirsiniz (rollback).

### Güvenli Helm Kurulumu

İnternet üzerindeki yükleme script'lerini doğrudan çalıştırmak yerine, işletim sisteminizin resmi paket yöneticisiyle yükleme yapılması önerilir:

```bash
# Ubuntu/Debian için:
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y
```

---

## 2. Temel Helm Komutları

Helm ile paket depolarını (repositories) yönetmek ve uygulamaları yönetmek için en sık kullanılan komutlar:

```bash
# 1. Paket Depoları (Repo) Yönetimi
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update                          # Tüm depoları güncelle

# 2. Chart (Paket) Arama
helm search repo postgresql               # Depolarda postgresql ara
helm search hub nginx                     # Genel Artifact Hub üzerinde ara

# 3. Paket Kurulumu (Install)
# bitnami/nginx paketini my-nginx adıyla my-namespace isim alanına kur:
helm install my-nginx bitnami/nginx \
  --namespace my-namespace \
  --create-namespace \
  -f custom-values.yaml

# 4. Listeleme ve Durum Sorgulama
helm list -A                              # Tüm isim alanlarındaki kurulumları göster
helm status my-nginx -n my-namespace      # Kurulumun detaylı durumunu sorgula

# 5. Güncelleme (Upgrade) ve Geri Alma (Rollback)
# values.yaml güncellendikten sonra paketi güncelle:
helm upgrade my-nginx bitnami/nginx -f custom-values.yaml

# Herhangi bir hata anında önceki sürüme (Örn: revizyon 1'e) geri dön:
helm rollback my-nginx 1 -n my-namespace

# 6. Paket Kaldırma (Uninstall)
helm uninstall my-nginx -n my-namespace
```

---

## 3. values.yaml ile Yapılandırma Özelleştirme

Bir Helm chart'ının varsayılan ayarlarını değiştirmek için kendi `values.yaml` dosyamızı yazarız.

```bash
# Bir chart'ın varsayılan parametre listesini dışa aktarın:
helm show values bitnami/nginx > default-values.yaml
```

### Örnek Özelleştirilmiş Değerler Dosyası (`my-values.yaml`)

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_manifest_1.yaml](../Manifests/09_gitops/helm_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Uygulamak için:
`helm install nginx bitnami/nginx -f my-values.yaml`

---

## 4. Kendi Helm Chart'ınızı Oluşturma

Kendi geliştirdiğiniz mikroservisleri paketlemek için yeni bir chart iskeleti oluşturabilirsiniz:

```bash
# Yeni chart dizini oluşturun
helm create my-app
```

### Chart Dizin Yapısı

```
my-app/
├── Chart.yaml          # Uygulama adı, sürümü ve açıklaması
├── values.yaml          # Şablonlarda kullanılacak varsayılan değişkenler
├── templates/           # Kubernetes YAML şablonları
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── _helpers.tpl     # Tekrar kullanılabilir adlandırma fonksiyonları
│   └── NOTES.txt        # Kurulum sonrası terminalde gösterilecek kılavuz
└── charts/              # Alt bağımlılıklar (varsa)
```

### Şablonları Test Etme ve Paketleme

```bash
# 1. Sözdizimi hatalarını denetle (Lint)
helm lint my-app/

# 2. Kümeye yüklemeden önce oluşacak gerçek YAML çıktılarını localde simüle et
helm template my-app my-app/ -f values.yaml

# 3. Chart klasörünü sıkıştırılmış bir arşiv (.tgz) haline getir
helm package my-app/
```

---

## 5. OCI Registry Entegrasyonu (Modern Dağıtım)

2026 yılı standartlarında Helm chart'ları, Docker imajları gibi **OCI (Open Container Initiative)** uyumlu kayıt defterlerinde (GitHub Packages - GHCR, Harbor vb.) depolanır ve dağıtılır:

```bash
# 1. OCI deposundan paket çekme (pull)
helm pull oci://ghcr.io/cert-manager/charts/cert-manager --version v1.16.0

# 2. OCI üzerinden doğrudan kurulum yapma
helm install cert-manager oci://ghcr.io/cert-manager/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.0 \
  --set crds.enabled=true
```

---

## 6. ArgoCD ile Helm Entegrasyonu (GitOps Akışı)

Modern GitOps mimarilerinde uygulamalar terminalden `helm install` ile kurulmaz. Bunun yerine ArgoCD, git reposundaki Helm chart'larını veya OCI depolarını dinleyerek kümeye otomatik deploy eder.

### ArgoCD Application CRD Tanımı ile Helm Kurulumu

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_manifest_2.yaml](../Manifests/09_gitops/helm_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

> [!TIP]
> **ArgoCD + Helm Uyarısı:** Bir uygulamayı ArgoCD Application kaynağı ile kurduğunuzda, bu kurulum doğrudan `helm list` komutunda görünmez. Çünkü ArgoCD chart şablonlarını API sunucusu üzerinde kendisi çözümler (render eder) ve doğrudan ham Kubernetes kaynakları olarak uygular. Durumu `kubectl get application -n argocd` ile izlemelisiniz.

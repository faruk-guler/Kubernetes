# Kustomize ile Deklaratif Yapılandırma Yönetimi (Kustomize Guide)

Kubernetes manifest dosyalarını yönetirken Helm gibi şablonlama (templating) araçları güçlü bir esneklik sunar. Ancak şablon yazmak istemeyen, ham Kubernetes YAML dosyalarına sadık kalmak ve sadece ortam bazlı (Dev, Staging, Prod) küçük değişiklikler yapmak isteyen ekipler için **Kustomize** en ideal çözümdür.

Kustomize, herhangi bir şablon motoru kullanmadan, ham YAML dosyalarını **yama (patch)** mantığıyla üst üste koyarak dinamik olarak birleştirir.

---

## 1. Helm ve Kustomize Karşılaştırması

| Karşılaştırma Kriteri | Helm | Kustomize |
|:---|:---:|:---:|
| **Şablonlama (Templating)** | ✅ Var (Go Template dili) | ❌ Yok (Şablonlama yapmaz) |
| **Harici Bağımlılık** | Evet (Helm CLI ve Tiller/Release yönetimi) | ❌ Yok (`kubectl` içinde yerleşik gelir) |
| **Öğrenme Kolaylığı** | Orta | Düşük / Kolay |
| **Üçüncü Parti Uygulamalar** | ✅ Çok Güçlü (Artifact Hub) | ⚠️ Sınırlı (Manuel yama gerektirir) |
| **Kendi Mikroservislerimiz** | Karmaşık (Chart yazma maliyeti) | ✅ Çok Pratik (Kullanımı kolay) |

---

## 2. Kustomize Kurulumu

Kustomize, Kubernetes'in resmi komut satırı aracı `kubectl` içine gömülü olarak gelir (v1.14+). Ekstra bir araç kurmadan `kubectl apply -k` komutuyla kustomize kurallarını kümeye uygulayabilirsiniz.

Bağımsız (standalone) CLI aracını kurmak için:

```bash
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo install -o root -g root -m 0755 kustomize /usr/local/bin/kustomize

# Doğrulama
kustomize version
```

---

## 3. Proje Klasör Mimarisi (Base & Overlays)

Kustomize, ortak yapılandırmaları `base` klasöründe toplar. Ortama özel (örneğin production veya development) parametreleri ise `overlays` dizinindeki yamalarla ezerek uygular.

```
my-app/
├── base/                        # Tüm ortamlarda ortak olan ham YAML dosyaları
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/                     # Geliştirme (development) ortamı
    │   ├── kustomization.yaml
    │   └── replica-patch.yaml   # replica sayısını 1 yap
    └── prod/                    # Canlı (production) ortamı
        ├── kustomization.yaml
        └── replica-patch.yaml   # replica sayısını 5 yap
```

---

## 4. Yapılandırma Dosyaları (base & overlays)

### A. `base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
```

### B. `overlays/prod/kustomization.yaml`

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kustomize_manifest_1.yaml](../Manifests/09_gitops/kustomize_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. `overlays/prod/replica-patch.yaml`

Deployment'taki replica değerini değiştiren basit yama:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app # base dizinindeki deployment ismiyle eşleşmelidir
spec:
  replicas: 5
```

---

## 5. JSON Patch (RFC 6902) ile Hassas Yama Uygulama

Bazen tüm YAML bloğunu ezmek yerine, YAML dosyasındaki tek bir satırı (örneğin bir çevre değişkenini veya resource limit değerini) değiştirmek isteyebilirsiniz. Bunun için JSON Patch standardı kullanılır.

### Örnek JSON Patch Yapılandırması

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kustomize_manifest_2.yaml](../Manifests/09_gitops/kustomize_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Temel Kustomize Komutları

```bash
# 1. Yamaların birleştirilmiş halini ekrana yazdırın (Cluster'a etki etmez - Simülasyon)
kustomize build overlays/prod
# Veya kubectl ile:
kubectl kustomize overlays/prod

# 2. Birleştirilmiş yapılandırmayı doğrudan kümeye uygulayın
kubectl apply -k overlays/prod

# 3. Kümdeki mevcut durum ile Kustomize çıktısı arasındaki farkları görün
kubectl diff -k overlays/prod
```

---

## 7. ArgoCD ile Kustomize Entegrasyonu (GitOps)

ArgoCD, Kustomize projelerini yerleşik (native) olarak destekler. Git deponuzda overlays klasörünü hedef gösterdiğinizde, ArgoCD kustomize derlemesini arka planda otomatik çalıştırır.

### ArgoCD Application Tanımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kustomize_manifest_3.yaml](../Manifests/09_gitops/kustomize_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

> [!TIP]
> **configMapGenerator ve Otomatik Restart Gücü:**
> Kustomize'da `configMapGenerator` kullandığınızda, ConfigMap içeriğindeki bir değişkeni değiştirdiğinizde, Kustomize üretilen ConfigMap isminin sonuna rastgele bir hash değeri ekler (Örn: `app-config-h78f8gf8fg`). Bu hash değiştiği için Deployment dosyası da güncellenir ve pod'larınız otomatik olarak yeni config değerleriyle yeniden başlatılır (rolling update). Ekstra bir Reloader kurmanıza gerek kalmaz.

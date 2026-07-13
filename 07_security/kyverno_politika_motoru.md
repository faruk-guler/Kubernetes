# Kyverno Politika Motoru (Kyverno Policy Engine)

Sistem yönetiminde kuralların insan kontrolüne bırakılması her zaman zafiyet yaratır. Kubernetes ekosisteminde **Policy-as-Code (Kod Olarak Politika)** felsefesiyle çalışan **Kyverno**, kümenizdeki tüm kaynak oluşturma, güncelleme ve silme süreçlerini deklaratif kurallarla denetler. OPA (Open Policy Agent) Gatekeeper gibi karmaşık programlama dilleri (Rego) gerektirmeyen Kyverno, tamamen alışkın olduğumuz Kubernetes YAML sözdizimini kullanır.

---

## 1. Kyverno Kurulumu (Helm)

Kyverno'nun üretim (production) ortamlarında yüksek kullanılabilirlik (HA) ile çalışabilmesi için kontrol düzlemi bileşenleri çoklu kopya (replica) şeklinde kurulmalıdır:

```bash
# 1. Helm deposunu ekleyin ve güncelleyin
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# 2. HA Modunda kurulum yapın
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3 \
  --set admissionController.replicas=3 \
  --set backgroundController.replicas=2 \
  --set cleanupController.replicas=1 \
  --set reportsController.replicas=1

# 3. Hazır PSS kurallarını içeren kütüphaneyi kurun
helm install kyverno-policies kyverno/kyverno-policies \
  --namespace kyverno \
  --set podSecurityStandard=restricted
```

---

## 2. Doğrulama (Validate) Politikaları

Doğrulama politikaları, API Server'a gelen istekleri denetler ve uymayanları engeller (`Enforce`) ya da sadece rapora ekler (`Audit`).

### A. Resource Limit Zorunluluğu

Tüm podların CPU ve Bellek (Memory) limitlerini tanımlamasını zorunlu kılmak için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_1.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Zorunlu Label (Etiket) Kontrolü

İsim alanlarındaki podlarda `environment` etiketinin olmasını zorunlu kılma:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_2.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. CEL ile Karmaşık Doğrulama (Kyverno v1.11+)

CEL kullanarak, bir pod içindeki container imajlarının sayısını denetleyen kural:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_3.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Dönüştürme (Mutate) Politikaları

Dönüştürme politikaları, gelen istekleri API sunucusunda kalıcı olmadan önce otomatik olarak modifiye eder.

### A. Otomatik Label (Etiket) Ekleme

Pod'un oluşturulduğu isim alanındaki `owner` bilgisini alıp, poda otomatik etiket olarak ekleme:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_4.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Resource Limit Ekleme (Varsayılan Atama)

Yazılımcı limit tanımlamayı unuttuysa, podu reddetmek yerine varsayılan kaynak değerlerini otomatik enjekte etme:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_5.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Oluşturma (Generate) Politikaları

Yeni bir Kubernetes nesnesi yaratıldığında (Örn: Namespace), tetiklenen bir kural aracılığıyla arka planda başka nesneleri (ConfigMap, Secret, NetworkPolicy) otomatik olarak üretir.

### Yeni Namespace Oluşturulunca Otomatik NetworkPolicy Tanımlama

Yeni bir namespace açıldığında, o namespace içindeki tüm dış trafiği kapatan varsayılan `deny-all` ağ kuralını otomatik oluşturma:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_6.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_6.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. İmaj Güvenliği (Image Security)

Kyverno, konteyner imajlarının imzalarını doğrulayabilir ve güvensiz registrylerden çekilmesini engelleyebilir.

### A. İmzalı İmaj Zorunluluğu (Cosign Entegrasyonu)

Kümede sadece **Cosign** ile imzalanmış güvenli imajların çalışmasına izin verme:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_7.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_7.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Latest Tag Yasağı ve Registry Kısıtlama

Üretimde `latest` etiketli veya yetkilendirilmemiş dış kaynaklı imaj kullanımını engelleme:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kyverno_politika_motoru_manifest_8.yaml](../Manifests/07_security/kyverno_politika_motoru_manifest_8.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. PolicyReport: Uyumluluk Raporları

Kyverno, kümedeki politikaların durumunu analiz etmek için CRD tabanlı raporlama sunar:

```bash
# 1. Belirli bir isim alanındaki politika raporunu listeleyin
kubectl get policyreport -n production

# 2. Sadece hata veren (FAIL) sonuçları yq ile filtreleyin
kubectl get policyreport -n production -o yaml | \
  yq '.items[].results[] | select(.result == "fail")'

# 3. Küme düzeyindeki (Cluster-wide) kaynakların raporları
kubectl get clusterpolicyreport

# 4. Tüm kümedeki ihlalleri jq kullanarak özet rapor olarak alın
kubectl get policyreport -A -o json | \
  jq '.items[] | .results[] | select(.result == "fail") | {policy: .policy, resource: .resources[0].name, message: .message}'
```

---

## 7. Kyverno CLI: GitOps ve CI/CD Entegrasyonu

Kyverno CLI, kuralları kümeye uygulamadan önce local makinenizde veya CI/CD boru hatlarında test etmenizi sağlar:

```bash
# Kyverno CLI Kurulumu (Linux/macOS)
curl -LO https://github.com/kyverno/kyverno/releases/latest/download/kyverno-cli_linux_x86_64.tar.gz
tar -xf kyverno-cli_*.tar.gz
sudo install kyverno /usr/local/bin/

# CI sürecinde politikayı test etme (GitHub Actions adımı)
- name: Kyverno Policy Test
  run: |
    # Kuralı pod YAML dosyası üzerinde test et
    kyverno apply ./policies/require-resources.yaml --resource ./k8s/deployment.yaml
```

> [!TIP]
> **Production Stratejisi:** Yeni bir politikayı ilk kez yayına alırken `validationFailureAction: Audit` (Gözlem) modunda çalıştırın. Raporları inceledikten ve hataları giderdikten sonra güvenle `Enforce` moduna geçin. Bu sayede üretim servislerinde beklenmeyen duruşları önlemiş olursunuz.

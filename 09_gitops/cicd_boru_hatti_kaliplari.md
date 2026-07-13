# CI/CD Boru Hattı Kalıpları (CI/CD Pipeline Patterns)

Kubernetes ile entegre çalışan CI/CD (Sürekli Entegrasyon / Sürekli Dağıtım) boru hatları, "kod commit edildiği an testlerin çalışması, imajın derlenmesi ve güvenli bir şekilde kümeye deploy edilmesi" sürecini uçtan uca otomatikleştirir. Bu dokümanda; modern CI/CD olgunluk seviyelerini, GitHub Actions entegrasyonunu, Kubernetes-native çalışan **Tekton** mimarisini ve GitOps entegrasyon pratiklerini inceleyeceğiz.

---

## 1. CI/CD Olgunluk Seviyeleri

| Seviye | Dağıtım Tarzı | Risk Seviyesi |
|:---:|:---|:---|
| **Seviye 0** | Manuel Dağıtım (`kubectl apply -f` terminalden). | 🔴 Çok Yüksek |
| **Seviye 1** | Script Tabanlı Dağıtım (CI sunucusu ssh ile bağlanıp kubectl çalıştırır). | 🔴 Yüksek |
| **Seviye 2** | Otomatik Boru Hattı (Derleme, test, push ve deploy adımları CI ile yapılır). | 🟡 Orta |
| **Seviye 3** | GitOps Mimarisi (CI sadece imaj üretir ve Git'i günceller, CD/ArgoCD senkronize eder). | 🟢 Düşük |
| **Seviye 4** | Progresif Teslimat (Canary deploy, metrik denetimleri ve otomatik rollback). | 🟢 En Güvenli |

---

## 2. GitHub Actions ile Kubernetes Dağıtımı (Seviye 2 Model)

Aşağıdaki iş akışı (workflow), bir kodu derleyip doğrudan bir Kubernetes kümesine `kubeconfig` kullanarak deploy eden temel yapıyı gösterir:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cicd_boru_hatti_kaliplari_manifest_1.yaml](../Manifests/09_gitops/cicd_boru_hatti_kaliplari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Tekton: Kubernetes-Native CI/CD Aracı

**Tekton**, CI/CD iş akışlarını Kubernetes podları ve CRD nesneleri olarak çalıştıran Kubernetes-native bir boru hattı motorudur.

### Kurulum

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
```

### A. Task (Temel Çalışma Birimi)

Tekton'da her adım (`Step`), tek bir pod içinde çalışan bir konteynerdir. Bu adımların birleşimi ise `Task` CRD'sini oluşturur.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cicd_boru_hatti_kaliplari_manifest_2.yaml](../Manifests/09_gitops/cicd_boru_hatti_kaliplari_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Pipeline (Task Zinciri)

Birden fazla Task'ı belirli bir sıra ve bağımlılıkla birbirine bağlayan yapı:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cicd_boru_hatti_kaliplari_manifest_3.yaml](../Manifests/09_gitops/cicd_boru_hatti_kaliplari_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. PipelineRun (Tetikleyici)

Yazılan bir Pipeline'ı fiilen çalıştırmak ve parametre göndermek için kullanılan nesnedir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cicd_boru_hatti_kaliplari_manifest_4.yaml](../Manifests/09_gitops/cicd_boru_hatti_kaliplari_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. GitOps ile CI/CD Entegrasyon Kalıbı (Seviye 3)

Modern GitOps sistemlerinde CI ve CD süreçleri kesin çizgilerle birbirinden ayrılmıştır:

```
[ Geliştirici Kod Push ]
          │
          ▼
┌──────────────────┐
│   CI (Github)    │ ──► (İmaj Derle, Tara ve Push Et)
└────────┬─────────┘
         │
         ▼ (Otomatik Git Commit & Push)
┌──────────────────┐
│   GitOps Repo    │ ──► (YAML dosyasındaki image tag'ini güncelle)
└────────┬─────────┘
         │
         ▼ (Pull & Sync)
┌──────────────────┐
│   CD (ArgoCD)    │ ──► (Kümeye uygula)
└──────────────────┘
```

### GitHub Actions Üzerinden GitOps Reposunu Otomatik Güncelleme Adımı

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [cicd_boru_hatti_kaliplari_manifest_5.yaml](../Manifests/09_gitops/cicd_boru_hatti_kaliplari_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. İmaj Güvenliği Taraması (Pipeline Entegrasyonu)

Boru hattı içinde derlenen imajlar, registry'e gönderilmeden hemen önce **Trivy** ile taranmalı ve kritik bir açık bulunduğunda pipeline derhal sonlandırılmalıdır:

```yaml
    - name: Run Trivy Vulnerability Scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: registry.company.com/my-app:${{ github.sha }}
        format: 'table'
        exit-code: '1' # Eşik değer aşılırsa build'i kır (hata verdir)
        ignore-unfixed: true
        severity: 'CRITICAL,HIGH'
```

---

## 6. En İyi Pratikler (Best Practices)

1. **CI ve CD'yi Ayırın:** CI sadece kod bütünlüğünü test etmeli, imaj üretmeli ve GitOps reposunu güncellemelidir. Kümeye doğrudan erişim yetkisi (kubectl yetkisi) CI sunucularına verilmemelidir.
2. **Sürüm Etiketleri:** Asla `latest` imaj etiketi kullanmayın. Her imajı Git commit SHA'sı veya SemVer (Semantik Sürüm) kurallarına göre etiketleyin.
3. **Hafif CI, Sıkı CD:** CI pipeline'ı geliştiriciye hızlı geri bildirim vermek için 5 dakikadan kısa sürmelidir. CD aşaması ise kademeli (canary) ve güvenli ilerlemelidir.

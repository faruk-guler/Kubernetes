# GitLab CI/CD ve Kubernetes Entegrasyonu Derinlemesine İnceleme

**GitLab**, hem kod sürüm yönetimini (Git) hem de gelişmiş CI/CD boru hatlarını tek bir çatı altında sunan entegre bir DevOps platformudur. GitLab'ın Kubernetes kümeleriyle entegrasyonu, geçmişteki statik sertifika paylaşım metotlarının ötesinde, modern ve çekme tabanlı (pull-based) çalışan **GitLab Agent for Kubernetes** ve GitLab Runner mimarilerine dayanır.

---

## 1. GitLab Agent for Kubernetes (KAS)

GitLab Agent, küme içinde çalışarak GitLab KAS (Kubernetes Agent Server) sunucusu ile güvenli bir gRPC/WebSocket bağlantısı kurar.

* **Güvenlik:** Kümenin dış dünyaya port açmasını veya kubeconfig dosyasının GitLab sunucularında saklanmasını gerektirmez (Pull-based). Küme güvenlik duvarının arkasında olsa bile çalışır.

### Kurulum (Helm)

```bash
# 1. GitLab UI üzerinden agent ekleyin ve token alın
# 2. Helm ile agent'ı kümenize kurun:
helm repo add gitlab https://charts.gitlab.io
helm repo update

helm install gitlab-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --create-namespace \
  --set config.token=<agent-token> \
  --set config.kasAddress=wss://kas.gitlab.com
```

### Agent Yapılandırması (`config.yaml`)

Agent'ın hangi git reposundaki hangi dosyaları izleyip otomatik senkronize edeceğini belirlemek için git projesinde `.gitlab/agents/<agent-adi>/config.yaml` dosyası oluşturulmalıdır:

```yaml
# .gitlab/agents/my-k8s-agent/config.yaml
gitops:
  manifest_projects:
  - id: my-group/my-gitops-infra # İzlenecek git reposu
    paths:
    - glob: '/manifests/**/*.yaml' # Sadece bu klasördeki YAML'ları izle
    - glob: '/manifests/**/*.yml'
```

---

## 2. Komple GitLab CI/CD Pipeline Örneği (`.gitlab-ci.yml`)

Aşağıda, Docker daemon'a ihtiyaç duymadan güvenli imaj derleyen (**Kaniko**), imajı tarayan (**Trivy**) ve sürüm etiketini manifestoya otomatik yazan komple bir `.gitlab-ci.yml` dosyası yer almaktadır:

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [gitlab_cicd_derinlemesine_inceleme_manifest_1.yaml](../Manifests/09_gitops/gitlab_cicd_derinlemesine_inceleme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. GitLab Environments (Ortamlar) ve Deployments

GitLab, uygulamaların hangi ortamlarda (Dev, Staging, Production) ne durumda olduğunu izlemek için **Environments** arayüzüne sahiptir.

* **İzlenebilirlik:** Hangi sürümün hangi sunucuda ne kadar süredir çalıştığını GitLab arayüzünden canlı izleyebilirsiniz.
* **Korumalı Ortamlar (Protected Environments):** Canlıya (Production) dağıtım adımlarının sadece belirli yetkililer (SRE, Team Lead) tarafından manuel olarak onaylanması (`when: manual` tetikleyicisiyle) sağlanabilir.

---

## 4. GitLab Auto DevOps (Hazır Boru Hattı)

Eğer projenizde sıfırdan CI/CD YAML dosyaları yazmak istemiyorsanız, GitLab'ın **Auto DevOps** özelliğini aktif edebilirsiniz. Auto DevOps; projedeki yazılım dilini otomatik algılar (Herokuish buildpacks kullanarak), testleri çalıştırır, imajı derler ve kubernetes kümenize Helm kullanarak otomatik deploy eder. Küçük projeler ve hızlı POC (Proof of Concept) çalışmaları için idealdir.

---

## 5. Yeniden Kullanılabilir Bileşenler (GitLab CI Components)

Farklı projelerdeki benzer CI/CD adımlarını (Örn: Her projede aynı Trivy taramasını çalıştırmak) tek merkezden yönetmek için GitLab 16.0+ ile gelen **CI/CD Components** yapısı kullanılır.

```yaml
# Başka bir projede bu komponenti dahil etmek (include):
include:
  - component: gitlab.com/my-shared-templates/trivy-scanner/scan@1.0.0
    inputs:
      image_name: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
```

Bu sayede her projede yüzlerce satır aynı kodu kopyalamak yerine, merkezi şablonlar referans alınarak standartlar korunur.

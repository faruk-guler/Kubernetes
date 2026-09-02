# GitHub Actions ve ARC (Actions Runner Controller)

Modern CI/CD dünyasında GitLab CI, Jenkins ve Tekton gibi araçların yanı sıra **GitHub Actions** fiili endüstri standardı haline gelmiştir. 

Ancak GitHub'ın bize sunduğu ücretsiz (veya ücretli) paylaşımlı "Runner" (Koşucu) makineleri bazı senaryolar için yetersiz kalır:
- Kodunuz dışarıya tamamen kapalı (air-gapped) bir iç ağda olabilir.
- Uygulama derlemek için devasa CPU ve RAM gücüne ihtiyaç duyabilirsiniz (Standart runner'lar 2 CPU / 7GB RAM'dir).
- Kod derleme işleminin, kodların dışarı çıkmadan **kendi veri merkezinizde** veya **kendi Kubernetes kümeniz içinde** gerçekleşmesini isteyebilirsiniz.

Bu noktada **Self-Hosted Runners** ve onu Kubernetes'te otomatize eden **ARC (Actions Runner Controller)** devreye girer.

---

## 1. ARC (Actions Runner Controller) Nedir?

ARC, Kubernetes üzerinde çalışan ve GitHub Actions Runner pod'larını ihtiyaca (bekleyen CI işlerine) göre otomatik olarak ölçeklendiren resmi bir Kubernetes Operatörüdür.

**Nasıl Çalışır?**
1. Geliştirici koda `push` yapar.
2. GitHub Webhook üzerinden ARC'ye bir bildirim gönderir (veya ARC düzenli API çeker).
3. ARC, Kubernetes kümenizde boşta bekleyen veya yeni oluşturduğu bir `Runner` pod'unu devreye sokar.
4. Runner pod'u işi tamamlar (kod derlenir, test edilir, imaj basılır) ve iş bitince pod silinir (Ephemeral yapısı).

---

## 2. ARC Kurulumu

ARC'yi kurmak için Helm kullanırız. Kurulumdan önce GitHub'dan bir **PAT (Personal Access Token)** veya **GitHub App** yetkilendirmesi almamız gerekir. Kurumsal ölçekte *GitHub App* kullanılması şiddetle önerilir.

```bash
# ARC Helm deposunu ekle
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# ARC Operatörünü Kur (Örnek olarak PAT ile)
helm upgrade --install --namespace actions-runner-system --create-namespace \
  --set=authSecret.create=true \
  --set=authSecret.github_token="ghp_SİZİN_GİZLİ_TOKENINIZ" \
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller
```

---

## 3. Runner Deployment (Koşucu Dağıtımı) Oluşturmak

Operatör kurulduktan sonra, kümeye "Bana şu özelliklerde bir Runner havuzu yarat" dememiz gerekir. Bunu `RunnerDeployment` CRD nesnesi ile yaparız.

Örnek bir manifest dosyası `manifests/10_github_actions_runner.yaml` içinde bulunabilir. 
Özetle şuna benzer:

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: k8s-runner
  namespace: actions-runner-system
spec:
  replicas: 1
  template:
    spec:
      repository: kullanici-adiniz/proje-adiniz # Veya organization seviyesinde
      labels:
        - "self-hosted"
        - "k8s-linux-amd64"
```

Bu nesneyi uyguladığınızda (`kubectl apply`), Kubernetes kümenizde GitHub Actions için iş bekleyen bir pod oluşacaktır.

---

## 4. Dinamik Ölçeklendirme (HPA / KEDA Entegrasyonu)

Eğer mesai saatleri içinde 50 geliştirici aynı anda kod pushlarsa, tek bir Runner yetmez. İşlerin (Jobs) sırada beklememesi için RunnerDeployment'ı otomatik ölçeklendirmeliyiz.

Bunu **HorizontalRunnerAutoscaler (HRA)** nesnesi ile yaparız:

```yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: k8s-runner-autoscaler
  namespace: actions-runner-system
spec:
  scaleTargetRef:
    name: k8s-runner
  minReplicas: 1
  maxReplicas: 20
  metrics:
  - type: PercentageRunnersBusy # Runner'ların doluluk oranına göre ölçekle
    scaleUpThreshold: '0.75'    # %75 doluysa yeni pod aç
    scaleDownThreshold: '0.30'
```

---

## 5. DinD (Docker-in-Docker) ve Güvenlik Uyarıları

Runner'lar genellikle imaj (Docker) derlemek zorundadır. Ancak bir Kubernetes podunun içinde Docker komutları çalıştırmak zordur.
ARC, varsayılan olarak **DinD (Docker in Docker)** kullanır. Runner pod'u aslında iki konteynerden oluşur:
1. `runner` konteyneri (GitHub ajanı çalışır)
2. `dind` konteyneri (Privileged yetkiyle çalışan docker daemon)

> **[CAUTION] Güvenlik Uyarısı:** DinD mimarisinde çalışan `dind` konteyneri **root (privileged)** yetkilere ihtiyaç duyar. Eğer çok katı güvenlik politikalarınız (Kyverno, OPA) varsa, DinD kurulumları reddedilebilir. 
> Çözüm olarak **Rootless Docker** veya Docker yerine **Kaniko / Buildah** gibi root yetkisi istemeyen araçları (Rootless build) tercih etmelisiniz.

## Özet
Kümenizde ARC kullanarak CI sürelerini dakikalardan saniyelere indirebilir, kaynak israfını (kullanılmayan sunucu parası) bitirebilir ve kurumsal verinizin sadece kendi veri merkezinizde (On-Prem) kalmasını garantileyebilirsiniz.

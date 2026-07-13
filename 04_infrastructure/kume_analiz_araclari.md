# Test ve Küme Analiz Araçları

Bir Kubernetes kümesi (cluster) dışarıdan bakıldığında tamamen sağlıklı görünebilir. Ancak arka planda deprecated (artık kaldırılmış) API çağrıları yapılıyor, kullanılmayan ve bellek yakan Secret/ConfigMap nesneleri birikiyor veya fark edilmeyen ciddi güvenlik açıkları barındırılıyor olabilir.

Bu bölümde, kümenizin "sağlık röntgenini" çekecek analiz araçlarını ve Kubernetes iş yüklerinizi test etmek için kullanılan modern test metodolojilerini ele alacağız.

---

## 1. Kubernetes Test Piramidi

Kubernetes ortamlarında test süreçleri, klasik yazılım testlerinden farklı olarak cluster kaynaklarının doğrulanmasını da içerir ve dört aşamadan oluşur:

```
         ┌───────────────────────────┐
         │     Chaos Engineering     │  ◄── Canlıda direnç testi (Chaos Mesh)
         ├───────────────────────────┤
         │      E2E YAML Tests       │  ◄── Kümede kaynak doğrulaması (KUTTL, Chainsaw)
         ├───────────────────────────┤
         │   Integration / Linting   │  ◄── Lokal test (Kind, Polaris, Kube-Linter)
         ├───────────────────────────┤
         │    Unit Tests (Go/Fake)   │  ◄── Operatör mantığı sahte client ile (testing)
         └───────────────────────────┘
```

---

## 2. Birim Testi (Go & Fake Client ile Controller Testi)

Kendi geliştirdiğiniz Kubernetes Operatörlerini veya özel kaynak denetleyicilerini (controller) test etmek için gerçek bir kümeye ihtiyaç duymadan, hafızada (in-memory) çalışan sahte bir `fake client` kullanılır:

```go
package main

import (
    "context"
    "testing"
    "github.com/stretchr/testify/assert"
    appsv1 "k8s.io/api/apps/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "sigs.k8s.io/controller-runtime/pkg/client/fake"
    "k8s.io/client-go/kubernetes/scheme"
)

func TestReconcile(t *testing.T) {
    // 1. Sahte bir Kubernetes Client'ı oluşturun ve içine test nesnesi koyun
    fakeClient := fake.NewClientBuilder().
        WithScheme(scheme.Scheme).
        WithObjects(&appsv1.Deployment{
            ObjectMeta: metav1.ObjectMeta{
                Name:      "test-deploy",
                Namespace: "default",
            },
            Spec: appsv1.DeploymentSpec{
                Replicas: int32Ptr(3),
            },
        }).Build()

    // 2. Test etmek istediğiniz kontrolörü (reconciler) çağırın
    ctx := context.Background()
    deployment := &appsv1.Deployment{}
    err := fakeClient.Get(ctx, types.NamespacedName{Name: "test-deploy", Namespace: "default"}, deployment)

    // 3. Doğrulama (Assert) işlemleri
    assert.NoError(t, err)
    assert.Equal(t, int32(3), *deployment.Spec.Replicas)
}
```

---

## 3. YAML Tabanlı E2E Testi: KUTTL ve Chainsaw

Kod yazmadan, sadece hazırladığınız YAML dosyalarının Kubernetes üzerinde istediğiniz gibi davranıp davranmadığını test etmek için **KUTTL (Kubernetes Test Tool)** veya modern alternatifi **Chainsaw** kullanılır.

### KUTTL Test Klasör Yapısı

```
tests/
  ├── kuttl-test.yaml    # Test yapılandırma dosyası
  └── e2e/
      └── deployment-test/
          ├── 00-install.yaml  # Adım 0: Deployment'ı uygula
          └── 01-assert.yaml   # Adım 1: Replikaların "3" olduğunu doğrula
```

### 01-assert.yaml (Doğrulama Dosyası)

KUTTL, belirtilen kaynağın durumunu (status) kontrol ederek testin başarılı olup olmadığına karar verir:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  status:
    readyReplicas: 3 # Eğer hazır replika sayısı 3 ise test PASS (başarılı) olur
```

Testi çalıştırmak için:

```bash
kubectl kuttl test --config tests/kuttl-test.yaml
```

---

## 4. Polaris ile Manifest Güvenlik ve Standart Taraması

**Polaris**, Kubernetes manifestlerinizi en iyi pratiklere (best practices) göre tarayarak not verir. CPU/RAM limitlerinin unutulması, root kullanıcısıyla çalışan podlar gibi açıkları tespit eder.

```bash
# Yerel manifest klasörünüzü tarayın (CI/CD süreçlerine entegre edilebilir)
polaris audit --audit-path ./k8s-manifests/ --format pretty
```

---

## 5. Kaos Mühendisliği: Chaos Mesh

Sistemlerin beklenmedik donanım ve ağ arızaları altında ayakta kalıp kalmadığını test etmek amacıyla, küme üzerinde planlı kaos yaratmak için **Chaos Mesh** kullanılır.

* **Kaos Örnekleri:** Rastgele podları öldürme (PodKill), ağa yapay gecikmeler ekleme (Network Delay), disk veya CPU doluluğunu yapay olarak artırma.

---

## 6. Küme Sağlık Röntgeni ve Analiz Araçları

Kümenizin sağlığını ölçen, kullanılmayan kaynakları ve sürüm uyumluluklarını tarayan en popüler 5 açık kaynaklı araç:

### 1. Popeye — Küme Temizleyici (Sanitizer)

Cluster'daki kullanılmayan ConfigMap/Secret nesnelerini, limitsiz podları ve yanlış yapılandırılmış servisleri tarayarak size A ile F arasında bir karne verir.

```bash
kubectl popeye -n production
```

### 2. Pluto — Kaldırılan (Deprecated) API Tespiti

Kubernetes sürüm yükseltmesi (Upgrade) yapmadan önce, manifestlerinizde artık kaldırılmış veya güncelliğini yitirmiş API sürümleri olup olmadığını tespit eder.

```bash
pluto detect-files -d ./manifests/ --target-versions k8s=v1.32
```

### 3. Nova — Helm Güncellik Analizi

Kümede kurulu olan Helm chart'larının güncel sürümlerini kontrol eder ve eskiyen bağımlılıkları raporlar.

```bash
nova find --wide
```

### 4. KubeCapacity — Kaynak Tüketim Tablosu

Kümedeki düğümlerin (nodes) ve podların rezerve edilen (requests/limits) kaynaklarını tek bir tabloda birleştirerek kolay okunabilir şekilde sunar.

```bash
kubectl resource-capacity --util --pods
```

### 5. Goldilocks — CPU/Memory Request Önerisi

Podlarınızın gerçek kullanım metriklerini izleyerek, VPA (Vertical Pod Autoscaler) verileri ışığında en ideal CPU ve RAM `request/limit` değerlerini görsel bir dashboard üzerinden önerir.

---

## 7. Özet

Kubernetes'te test ve analiz araçları, sistemin gelecekteki kararlılığını garanti altına almanın tek yoludur. **Pluto** ile kaldırılan API'lerin, **Popeye** ile israf edilen kaynakların ve **Polaris** ile güvenlik açıklarının taranması, kümenizin her zaman sağlıklı ve en iyi standartlarda (production-ready) kalmasını sağlar.

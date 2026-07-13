# Kubernetes Üzerinde Test Metodolojileri

Bir Kubernetes kümesi için uygulama geliştirirken veya kümenin kendisini yönetirken, yaptığımız yapılandırmaların ve yazdığımız kodların doğruluğunu test etmek kritik önem taşır. Kubernetes ekosisteminde test süreçleri, klasik yazılım testlerinden farklı olarak cluster kaynaklarının doğrulanmasını da içerir.

Bu bölümde; birim (unit) testlerden, YAML tabanlı uçtan uca (E2E) testlere ve kaos mühendisliği direnç testlerine kadar uzanan modern test metodolojilerini ele alacağız.

---

## 1. Kubernetes Test Piramidi

Kubernetes test süreçleri dört temel aşamadan oluşur:

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

Kendi geliştirdiğiniz Kubernetes Operatörlerini veya özel kaynak denetleyicilerini (controller) test etmek için gerçek bir kümeye ihtiyaç duymadan, hafızada (in-memory) çalışan sahte bir `fake client` kullanılır.

Bu sayede API Server'a gerçek HTTP çağrıları yapmadan, kube-apiserver davranışlarını taklit edebiliriz:

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

### KUTTL Test Klasör Yapısı:
```text
tests/
  ├── kuttl-test.yaml    # Test yapılandırma dosyası
  └── e2e/
      └── deployment-test/
          ├── 00-install.yaml  # Adım 0: Deployment'ı uygula
          └── 01-assert.yaml   # Adım 1: Replikaların "3" olduğunu doğrula
```

KUTTL, belirtilen kaynağın durumunu (status) kontrol ederek testin başarılı olup olmadığına karar verir.

📌 **Örnek Doğrulama Manifesti:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [kuttl_assert.yaml](../Manifests/03_architecture/kuttl_assert.yaml) adresinden inceleyebilirsiniz.

Testi çalıştırmak için şu komut kullanılır:
```bash
kubectl kuttl test --config tests/kuttl-test.yaml
```

---

## 4. Kaos Mühendisliği (Chaos Engineering): Chaos Mesh

Sistemlerin beklenmedik donanım ve ağ arızaları altında ayakta kalıp kalmadığını test etmek amacıyla, küme üzerinde planlı kaos yaratmak için **Chaos Mesh** kullanılır.

* **Kaos Örnekleri:**
  - **PodKill:** Belirli aralıklarla rastgele pod'ları öldürerek sistemin self-healing (kendi kendini iyileştirme) hızını ölçer.
  - **Network Chaos:** Konteynerler arası iletişime yapay gecikmeler (latency) veya paket kayıpları (packet loss) ekler.
  - **Stress Chaos:** Pod'lara yapay olarak CPU ve bellek yükü bindirerek limitlerin doğru çalışıp çalışmadığını test eder.

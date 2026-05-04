# Kubernetes Üzerinde Test Stratejileri

Kubernetes iş yüklerini test etmek, sıradan uygulama testinden farklıdır. Cluster davranışını, kaynak yönetimini ve operatör mantığını doğrulamak için özel araçlar gerekir.

---

## Test Piramidi — Kubernetes Versiyonu

```
         ╔══════════════════╗
         ║   E2E / Chaos    ║  ← Gerçek cluster, yavaş, pahalı
         ╠══════════════════╣
         ║  Entegrasyon     ║  ← Kind/k3d, servisler birlikte
         ╠══════════════════╣
         ║  Unit / Contract ║  ← Hızlı, mock'lu, ucuz
         ╚══════════════════╝
```

---

## 1. Unit Test — Controller & Operator Mantığı

```go
// Kubebuilder Operator'ı test etme (Go)
import (
    "testing"
    "sigs.k8s.io/controller-runtime/pkg/client/fake"
    "k8s.io/client-go/kubernetes/scheme"
)

func TestReconcile(t *testing.T) {
    // Sahte Kubernetes client oluştur
    fakeClient := fake.NewClientBuilder().
        WithScheme(scheme.Scheme).
        WithObjects(&myv1.MyApp{
            ObjectMeta: metav1.ObjectMeta{
                Name:      "test-app",
                Namespace: "default",
            },
            Spec: myv1.MyAppSpec{
                Replicas: 3,
                Image:    "nginx:latest",
            },
        }).
        Build()

    reconciler := &MyAppReconciler{Client: fakeClient}

    // Reconcile'ı çalıştır
    result, err := reconciler.Reconcile(context.Background(),
        reconcile.Request{NamespacedName: types.NamespacedName{
            Name:      "test-app",
            Namespace: "default",
        }},
    )

    assert.NoError(t, err)
    assert.False(t, result.Requeue)

    // Deployment oluşturuldu mu?
    deployment := &appsv1.Deployment{}
    err = fakeClient.Get(context.Background(),
        types.NamespacedName{Name: "test-app", Namespace: "default"},
        deployment,
    )
    assert.NoError(t, err)
    assert.Equal(t, int32(3), *deployment.Spec.Replicas)
}
```

---

## 2. Entegrasyon Testi — Kind ile

```yaml
# .github/workflows/integration.yaml
name: Integration Tests

on: [pull_request]

jobs:
  integration:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Setup Kind
      uses: helm/kind-action@v1
      with:
        config: .github/kind-config.yaml

    - name: Load image to Kind
      run: |
        docker build -t my-app:test .
        kind load docker-image my-app:test

    - name: Deploy to Kind
      run: |
        kubectl apply -f k8s/
        kubectl wait --for=condition=available deployment/my-app --timeout=60s

    - name: Run integration tests
      run: |
        kubectl port-forward svc/my-app 8080:80 &
        sleep 3
        pytest tests/integration/ -v
```

```yaml
# .github/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
```

---

## 3. KUTTL — Kubernetes Test Aracı

KUTTL (KUbernetes Test TooL), YAML dosyalarıyla K8s kaynaklarını test eder — kod yazmadan.

```bash
# KUTTL kurulumu
kubectl krew install kuttl
# veya
brew install kuttl
```

```
# Test dosya yapısı
tests/
  kuttl-test.yaml         ← Test suite konfigürasyonu
  e2e/
    deployment-test/
      00-install.yaml      ← Adım 0: Kaynakları kur
      01-assert.yaml       ← Adım 1: Durumu doğrula
      02-delete.yaml       ← Adım 2: Sil ve temizle
      03-assert.yaml       ← Adım 3: Silindiğini doğrula
```

```yaml
# kuttl-test.yaml
apiVersion: kuttl.dev/v1beta1
kind: TestSuite
startKIND: true           # Kind cluster otomatik başlat
kindConfig: kind-config.yaml
testDirs:
- tests/e2e
timeout: 120              # Saniye
```

```yaml
# 00-install.yaml — Kaynakları kur
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-app
spec:
  selector:
    app: web
  ports:
  - port: 80
```

```yaml
# 01-assert.yaml — Bu durum gerçekleşene kadar bekle
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
status:
  availableReplicas: 2    # 2 replica hazır olmalı
  readyReplicas: 2
```

```bash
# Test çalıştır
kubectl kuttl test
# --- PASS: deployment-test (23.45s)
# PASS
```

---

## 4. Chainsaw — Modern KUTTL Alternatifi

Kyverno ekibinin geliştirdiği, daha esnek ve okunabilir test aracı.

```bash
# Kurulum
brew install kyverno/tap/chainsaw
```

```yaml
# chainsaw-test.yaml
apiVersion: chainsaw.kyverno.io/v1alpha1
kind: Test
metadata:
  name: deployment-lifecycle
spec:
  steps:
  # Adım 1: Kur
  - name: deploy
    try:
    - apply:
        file: manifests/deployment.yaml
    - assert:
        file: assert/deployment-ready.yaml

  # Adım 2: Güncelle
  - name: update-image
    try:
    - patch:
        file: patches/update-image.yaml
    - assert:
        file: assert/rollout-complete.yaml

  # Adım 3: Hata senaryosu
  - name: test-failure-recovery
    try:
    - script:
        content: |
          kubectl delete pod -l app=web -n $NAMESPACE
    - assert:
        file: assert/pod-recovered.yaml
    catch:
    - describe:
        apiVersion: v1
        kind: Pod
```

---

## 5. Polaris — Kubernetes Best Practice Lint

```bash
# Helm kurulumu
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install polaris fairwinds-stable/polaris --namespace polaris --create-namespace

# CLI ile manifest kontrol (CI/CD için)
polaris audit --audit-path ./k8s/ --format pretty

# Mevcut cluster'ı tara
polaris audit --kubeconfig ~/.kube/config --format score
```

```yaml
# polaris-config.yaml — özelleştir
checks:
  # Zorunlu kontroller
  cpuRequestsMissing: error
  memoryRequestsMissing: error
  cpuLimitsMissing: warning
  memoryLimitsMissing: error
  livenessProbeMissing: warning
  readinessProbeMissing: error
  runAsRootAllowed: error
  privilegeEscalationAllowed: error
  hostNetworkSet: error
  notReadOnlyRootFilesystem: warning
  tagNotSpecified: error       # latest tag yasak
  pullPolicyNotAlways: warning
```

---

## 6. Chaos Engineering — Chaos Mesh

Kasıtlı hata üretip sistemin dayanıklılığını test et.

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh --namespace chaos-testing --create-namespace
```

```yaml
# Pod'u rastgele öldür
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-failure-test
  namespace: chaos-testing
spec:
  action: pod-failure
  mode: one
  selector:
    namespaces: [production]
    labelSelectors:
      app: api
  duration: "60s"
  scheduler:
    cron: "@every 10m"    # Her 10 dakika tetikle
---
# Network gecikme ekle
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay
spec:
  action: delay
  mode: all
  selector:
    namespaces: [production]
    labelSelectors:
      app: api
  delay:
    latency: "200ms"
    jitter: "50ms"
  duration: "5m"
---
# CPU baskısı uygula
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress
spec:
  mode: one
  selector:
    namespaces: [production]
  stressors:
    cpu:
      workers: 4
      load: 80    # %80 CPU yükü
  duration: "5m"
```

---

## Test Stratejisi Özeti

| Seviye | Araç | Ne Zaman |
|:-------|:-----|:---------|
| Unit | Go testing + fake client | Her commit |
| Lint | Polaris, kube-linter | CI/CD gate |
| Entegrasyon | Kind + pytest | Her PR |
| E2E YAML | KUTTL / Chainsaw | Her release |
| Chaos | Chaos Mesh | Haftalık/Aylık |

> [!TIP]
> CI/CD pipeline'a **Polaris**'i zorunlu gate olarak ekleyin — `cpuRequestsMissing` ve `memoryRequestsMissing` hatası olan manifest'leri merge'e izin vermeyin. Bu tek adım, resource management sorunlarının %80'ini önler.

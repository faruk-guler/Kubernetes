# Cluster Analysis Tools

Cluster'ın sağlığını, güvenliğini ve kaynak kullanımını analiz eden araçlar. Sorun çıkmadan önce tespit etmek için kullanılır.

---

## Popeye — Cluster Sanitizer

Cluster'daki Kubernetes kaynaklarını tarar, potansiyel sorunları (kullanılmayan ConfigMap, yanlış resource limit, sağlıksız pod vb.) raporlar.

```bash
# Kurulum
brew install popeye    # macOS
kubectl krew install popeye

# Tüm cluster taraması
kubectl popeye

# Belirli namespace
kubectl popeye -n production

# Sadece belirli kaynaklar
kubectl popeye -s pod,svc,deploy

# Raporu dosyaya kaydet
kubectl popeye --save --out html --output-file /tmp/report.html

# Spin format (renksiz, CI için)
kubectl popeye --out junit --output-file results.xml
```

**Popeye Puan Sistemi:**
```
A → Mükemmel (0-25 hata)
B → Kabul edilebilir
C → Dikkat gerekiyor
D → Acil müdahale
E → Kritik
F → Felaket
```

**Sık tespit edilen sorunlar:**
```
⚠️  No resource limits/requests set
⚠️  No liveness/readiness probe
⚠️  Unused ConfigMaps or Secrets
⚠️  Image using :latest tag
⚠️  Service has no associated pods
⚠️  Pod in non-running state
⚠️  High CPU/Memory pressure
```

---

## Pluto — Deprecated API Tespiti

K8s versiyonu yükseltmeden önce cluster'daki ve Helm chart'larındaki deprecated API'leri tespit eder.

```bash
# Kurulum
brew install FairwindsOps/tap/pluto    # macOS
kubectl krew install pluto

# Cluster'daki deprecated resource'lar
kubectl pluto detect-helm \
  --target-versions k8s=v1.32

# Manifest dosyalarını tara
pluto detect-files \
  -d ./k8s-manifests/ \
  --target-versions k8s=v1.32

# Helm chart'ları tara
helm template my-release ./charts/app | \
  pluto detect -

# CI/CD — deprecated varsa pipeline'ı durdur
pluto detect-helm \
  --target-versions k8s=v1.32 \
  --only-show-removed    # Sadece tamamen kaldırılmış olanlar (hata çıkar)

# Tüm API değişikliklerini göster
pluto list-targets-versions
```

```yaml
# GitHub Actions entegrasyonu
- name: Check for deprecated APIs
  run: |
    pluto detect-helm \
      --target-versions k8s=v1.32 \
      --ignore-deprecations    # Deprecation'ları görmezden gel
    # --only-show-removed ile tam hata al
```

---

## kube-bench — CIS Benchmark Taraması

Kubernetes cluster'ının CIS (Center for Internet Security) benchmark'larına uygunluğunu kontrol eder.

```bash
# Kurulum (her node'da çalışmalı)
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# Sonuçları oku
kubectl logs job/kube-bench

# Sadece belirli kontroller
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-node
spec:
  template:
    spec:
      containers:
      - name: kube-bench
        image: docker.io/aquasec/kube-bench:latest
        command: ["kube-bench", "node",
          "--benchmark", "cis-1.9",
          "--json"]
      restartPolicy: Never
      hostPID: true
      nodeSelector:
        kubernetes.io/os: linux
EOF

# Lokal çalıştır (control plane node'unda)
./kube-bench --config-dir cfg --config cfg/config.yaml

# Rapor formatları
kube-bench --json > report.json
kube-bench --junit > report.xml
```

**CIS Benchmark Kategorileri:**
```
[INFO]  → Bilgi, aksiyon gerekmez
[PASS]  → ✅ Geçti
[WARN]  → ⚠️  Manuel kontrol gerekiyor
[FAIL]  → ❌ Güvenlik ihlali — düzelt
```

---

## KubeCapacity — Kaynak Doluluk Tablosu

```bash
# Kurulum
kubectl krew install resource-capacity

# Node kaynak kullanımı
kubectl resource-capacity
# NODE          CPU REQUESTS  CPU LIMITS   MEM REQUESTS  MEM LIMITS
# node-1        850m/4000m    2200m/4000m  1.2Gi/8Gi     3.5Gi/8Gi
# node-2        1200m/4000m   3100m/4000m  2.1Gi/8Gi     5.2Gi/8Gi

# Pod bazlı detay
kubectl resource-capacity --pods -n production

# Yalnızca kullanılan kaynaklar
kubectl resource-capacity --util

# Tüm namespace'ler
kubectl resource-capacity --pods --util
```

---

## Goldilocks — Resource Önerisi

VPA (Vertical Pod Autoscaler) verilerini analiz ederek pod'lar için optimum CPU/Memory request/limit değerleri önerir.

```bash
# Helm ile kur
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install goldilocks fairwinds-stable/goldilocks \
  --namespace goldilocks \
  --create-namespace

# Namespace'i analiz için işaretle
kubectl label namespace production goldilocks.fairwinds.com/enabled=true

# Dashboard
kubectl port-forward svc/goldilocks-dashboard -n goldilocks 8080:80
# http://localhost:8080 → Her pod için önerilen değerler
```

---

## Nova — Helm Chart Güncelleme Analizi

```bash
# Kurulum
brew install FairwindsOps/tap/nova

# Cluster'daki eski Helm chart'ları bul
nova find --wide

# Belirli chart kontrol
nova find --wide | grep cilium

# JSON çıktı (CI için)
nova find --format json > outdated-charts.json
```

---

## Araç Seçim Özeti

| Araç | Ne Zaman? |
|:-----|:----------|
| **Popeye** | Genel cluster sağlığı denetimi |
| **Pluto** | K8s upgrade öncesi deprecated API tespiti |
| **kube-bench** | Güvenlik uyumluluk denetimi (CIS) |
| **KubeCapacity** | Kaynak kullanımı görselleştirme |
| **Goldilocks** | CPU/Memory request optimizasyonu |
| **Nova** | Helm chart versiyon güncellik kontrolü |

```bash
# Hızlı cluster sağlık kontrolü — tüm araçları çalıştır
echo "=== Popeye ===" && kubectl popeye -n production --out html
echo "=== Pluto ===" && pluto detect-helm --target-versions k8s=v1.32
echo "=== Nova ===" && nova find --wide
echo "=== KubeCapacity ===" && kubectl resource-capacity --util
```

> [!TIP]
> Bu araçları CI/CD pipeline'ınıza entegre edin. **Pluto** her deployment öncesi, **kube-bench** haftalık, **Popeye** günlük çalıştırılabilir.

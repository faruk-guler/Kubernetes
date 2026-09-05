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

Doğrulama politikaları, API Server'a gelen istekleri denetler ve kurallara uymayanları engeller (`Enforce`) ya da uyarı raporuna ekler (`Audit`).

### A. Temel Politika Yapısı (ClusterPolicy Şablonu)

Tüm podların kaynak (`resources.limits`) tanımlamasını zorunlu kılan eksiksiz bir `ClusterPolicy` şablonu:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resources
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-memory-and-cpu
      match:
        resources:
          kinds: [Pod]
      validate:
        message: "CPU ve Memory limitleri zorunludur!"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    memory: "?*"
```

---

### B. Zorunlu Label (Etiket) Kuralı

Pod oluşturulurken `environment` etiketinin varlığını denetleyen kural bloğu:

```yaml
rules:
  - name: check-for-environment
    match:
      resources:
        kinds: [Pod]
    validate:
      message: "Tüm podlar 'environment' etiketi içermelidir."
      pattern:
        metadata:
          labels:
            environment: "?*"
```

---

### C. CEL ile Gelişmiş Doğrulama (Kyverno v1.11+)

CEL (Common Expression Language) kullanarak pod içindeki konteyner sayısını en fazla 3 ile sınırlayan kural bloğu:

```yaml
rules:
  - name: limit-container-count
    match:
      resources:
        kinds: [Pod]
    validate:
      cel:
        expressions:
          - expression: "size(object.spec.containers) <= 3"
            message: "Bir pod içinde en fazla 3 konteyner yer alabilir."
```

---

## 3. Dönüştürme (Mutate) Politikaları

Dönüştürme politikaları, istekleri etcd'ye yazılmadan önce yakalar ve eksik alanları otomatik olarak tamamlar veya değiştirir.

### A. Otomatik Label (Etiket) Ekleme

Pod'un yaratıldığı isim alanındaki `owner` bilgisini pod etiketlerine otomatik aktaran kural:

```yaml
rules:
  - name: add-owner-label
    match:
      resources:
        kinds: [Pod]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            owner: "{{request.namespace}}"
```

### B. Varsayılan Kaynak Limiti Atama (Default Fallback)

Yazılımcı kaynak sınırı belirtmediyse podu reddetmek yerine varsayılan limitleri otomatik ekleyen kural:

```yaml
rules:
  - name: inject-default-resources
    match:
      resources:
        kinds: [Pod]
    mutate:
      patchStrategicMerge:
        spec:
          containers:
            - (name): "?*"
              +(resources):
                +(requests):
                  +(cpu): "100m"
                  +(memory): "128Mi"
```

---

## 4. Oluşturma (Generate) Politikaları

Yeni bir Kubernetes nesnesi yaratıldığında (örneğin yeni bir `Namespace`), arka planda bağlı diğer kaynakları (NetworkPolicy, Secret vb.) otomatik olarak üretir:

```yaml
rules:
  - name: default-deny-networkpolicy
    match:
      resources:
        kinds: [Namespace]
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: default-deny
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec:
          podSelector: {}
          policyTypes: [Ingress, Egress]
```

---

## 5. İmaj Güvenliği ve Doğrulama (Image Security)

Kyverno, konteyner imajlarının dijital imzalarını ve yetkili depolarını (registries) zorunlu kılabilir.

### A. Cosign ile Dijital İmza Doğrulama

Sadece onaylı açık anahtar (public key) ile imzalanmış güvenli imajların çalışmasına izin veren kural:

```yaml
rules:
  - name: verify-cosign-signature
    match:
      resources:
        kinds: [Pod]
    verifyImages:
      - imageReferences: ["*"]
        attestors:
          - entries:
              - keys:
                  publicKeys: |-
                    -----BEGIN PUBLIC KEY-----
                    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                    -----END PUBLIC KEY-----
```

### B. Latest Etiketi Yasağı ve Özel Depo Zorunluluğu

Üretim ortamlarında `latest` etiketini engelleyip sadece şirket içi onaylı depoyu zorunlu kılan kural:

```yaml
rules:
  - name: restrict-image-registries
    match:
      resources:
        kinds: [Pod]
    validate:
      message: "İmajlar onaylı depodan çekilmeli ve 'latest' etiketi kullanılmamalıdır."
      pattern:
        spec:
          containers:
            - image: "registry.company.com/*:!latest"
```

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

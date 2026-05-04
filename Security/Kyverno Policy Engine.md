# Kyverno ile Policy-as-Code

Manuel denetim yerine kuralları YAML olarak tanımlayıp Kubernetes'in bunları zorlamasını sağlarız. Kyverno, `kubectl` ile tanıdık YAML sözdizimini kullanarak karmaşık politika yönetimi yapar — OPA Rego bilgisi gerektirmez.

---

## Kurulum

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# HA kurulum (production)
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3 \
  --set admissionController.replicas=3 \
  --set backgroundController.replicas=2 \
  --set cleanupController.replicas=1 \
  --set reportsController.replicas=1

# Policy raporlarını görüntülemek için kyverno-policies
helm install kyverno-policies kyverno/kyverno-policies \
  --namespace kyverno \
  --set podSecurityStandard=restricted
```

---

## Doğrulama (Validate) Politikaları

### Resource Limit Zorunluluğu

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce    # Audit: sadece raporla, Enforce: reddet
  background: true                     # Mevcut resource'ları da kontrol et
  rules:
  - name: check-container-limits
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: ["*"]
    exclude:
      any:
      - resources:
          namespaces: [kube-system, kyverno]    # Sistem namespace'leri hariç tut
    validate:
      message: "Tüm container'lar için CPU ve Memory limiti zorunludur"
      pattern:
        spec:
          containers:
          - resources:
              limits:
                cpu: "?*"
                memory: "?*"
              requests:
                cpu: "?*"
                memory: "?*"
```

### Label Zorunluluğu

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-team-label
    match:
      any:
      - resources:
          kinds: [Deployment, StatefulSet, DaemonSet]
    validate:
      message: "'team', 'environment' ve 'app.kubernetes.io/version' label'ları zorunludur"
      pattern:
        metadata:
          labels:
            team: "?*"
            environment: "?*"
            app.kubernetes.io/version: "?*"
```

### CEL ile Karmaşık Doğrulama (Kyverno v1.11+)

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-replicas
spec:
  validationFailureAction: Enforce
  rules:
  - name: min-replicas-production
    match:
      any:
      - resources:
          kinds: [Deployment]
          namespaces: [production]
    validate:
      cel:
        expressions:
        - expression: "object.spec.replicas >= 2"
          message: "Production namespace'de minimum 2 replica gereklidir"
        - expression: "object.spec.template.spec.containers.all(c, has(c.readinessProbe))"
          message: "Tüm container'larda readinessProbe zorunludur"
```

---

## Dönüştürme (Mutate) Politikaları

### Otomatik Label Ekleme

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-labels
spec:
  rules:
  - name: add-managed-by
    match:
      any:
      - resources:
          kinds: [Deployment, StatefulSet]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            managed-by: kyverno
            last-modified: "{{request.object.metadata.creationTimestamp}}"
```

### Resource Limit Ekleme (Yoksa)

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-limits
spec:
  rules:
  - name: set-default-limits
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: [development]
    mutate:
      foreach:
      - list: "request.object.spec.containers"
        patchStrategicMerge:
          spec:
            containers:
            - (name): "{{element.name}}"
              resources:
                limits:
                  +(cpu): "500m"      # Sadece tanımlı değilse ekle
                  +(memory): "512Mi"
                requests:
                  +(cpu): "100m"
                  +(memory): "128Mi"
```

---

## Oluşturma (Generate) Politikaları

### Namespace Oluşturulunca Otomatik NetworkPolicy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: auto-generate-netpol
spec:
  rules:
  - name: default-deny-ingress
    match:
      any:
      - resources:
          kinds: [Namespace]
          selector:
            matchLabels:
              managed: "true"    # Sadece bu label'lı namespace'lerde
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: default-deny-all
      namespace: "{{request.object.metadata.name}}"
      synchronize: true         # Namespace değişirse policy'yi güncelle
      data:
        spec:
          podSelector: {}
          policyTypes: [Ingress, Egress]

  - name: allow-dns-egress
    match:
      any:
      - resources:
          kinds: [Namespace]
          selector:
            matchLabels:
              managed: "true"
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: allow-dns
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec:
          podSelector: {}
          policyTypes: [Egress]
          egress:
          - ports:
            - port: 53
              protocol: UDP
            - port: 53
              protocol: TCP
```

---

## Image Güvenliği

### İmzalı Image Zorunluluğu

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
spec:
  validationFailureAction: Enforce
  background: false
  rules:
  - name: check-image-signature
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: [production, staging]
    verifyImages:
    - imageReferences:
      - "ghcr.io/company/*"
      attestors:
      - count: 1
        entries:
        - keyless:
            subject: "https://github.com/company/*"
            issuer: "https://token.actions.githubusercontent.com"
            rekor:
              url: https://rekor.sigstore.dev
      mutateDigest: true      # Tag'i digest'e dönüştür (immutability)
      verifyDigest: true
```

### Latest Tag Yasağı ve Registry Kısıtlama

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-usage
spec:
  validationFailureAction: Enforce
  rules:
  - name: no-latest-tag
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "'latest' tag yasaktır — semver veya SHA digest kullanın"
      foreach:
      - list: "request.object.spec.containers"
        deny:
          conditions:
            any:
            - key: "{{element.image}}"
              operator: Equals
              value: "*:latest"
            - key: "{{element.image}}"
              operator: NotIn
              value: ["ghcr.io/company/*", "registry.company.com/*"]
```

---

## PolicyReport — Uyumluluk Raporları

```bash
# Namespace bazlı policy raporu
kubectl get policyreport -n production
kubectl get policyreport -n production -o yaml | \
  yq '.items[].results[] | select(.result == "fail")'

# Cluster seviyesi rapor
kubectl get clusterpolicyreport

# Kyverno CLI ile pre-deploy test
kyverno apply ./policies/ --resource pod.yaml
kyverno test ./policy-tests/

# Tüm namespace'lerdeki ihlaller
kubectl get policyreport -A -o json | \
  jq '.items[] | .results[] | select(.result == "fail") | {policy: .policy, resource: .resources[0].name, msg: .message}'
```

---

## Kyverno CLI — GitOps Entegrasyonu

```bash
# Kyverno CLI kurulumu
curl -LO https://github.com/kyverno/kyverno/releases/latest/download/kyverno-cli_linux_x86_64.tar.gz
tar -xf kyverno-cli_*.tar.gz
install kyverno /usr/local/bin/

# CI'da policy testi (GitHub Actions)
- name: Kyverno Policy Test
  run: |
    kyverno apply ./policies/require-labels.yaml \
      --resource ./k8s/deployment.yaml
    kyverno test ./policy-tests/
```

> [!TIP]
> `validationFailureAction: Audit` ile politikayı önce gözlem modunda çalıştırın. `kubectl get policyreport -A` ile mevcut ihlalleri görüp düzelttikten sonra `Enforce`'a geçin — bu önce-sonra yaklaşımı production kesintisini önler.

# Kyverno ile Policy-as-Code

## 2.1 Neden Kyverno?

Manuel denetim yerine kuralları YAML olarak tanımlayıp Kubernetes'in bunları zorlamasını sağlarız. Kyverno, `kubectl` ile tanıdık YAML sözdizimini kullanarak karmaşık politika yönetimi yapmanızı sağlar.

```bash
# Kyverno kurulumu (Helm)
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace
```

## 2.2 Doğrulama (Validation) Politikaları

### Resource Limit Zorunluluğu

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce         # Reddet (Audit: sadece raporla)
  background: true
  rules:
  - name: check-container-limits
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Tüm konteynerler için CPU ve Memory limiti tanımlanmalıdır!"
      pattern:
        spec:
          containers:
          - resources:
              limits:
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
          kinds: [Deployment, StatefulSet]
    validate:
      message: "'team' ve 'environment' label'ları zorunludur"
      pattern:
        metadata:
          labels:
            team: "?*"
            environment: "?*"
```

## 2.3 Dönüştürme (Mutation) Politikaları

Pod'lara otomatik label veya annotation eklemek:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-labels
spec:
  rules:
  - name: add-managed-by-label
    match:
      any:
      - resources:
          kinds: [Deployment]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            managed-by: kyverno
            created-at: "{{request.object.metadata.creationTimestamp}}"
```

## 2.4 Oluşturma (Generation) Politikaları

Namespace oluşturulduğunda otomatik NetworkPolicy üret:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-networkpolicy-on-namespace
spec:
  rules:
  - name: default-deny
    match:
      any:
      - resources:
          kinds: [Namespace]
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: default-deny-all
      namespace: "{{request.object.metadata.name}}"
      data:
        spec:
          podSelector: {}
          policyTypes:
          - Ingress
          - Egress
```

## 2.5 Pod Security Standards (PSS)

Kubernetes, yerleşik 3 güvenlik seviyesi sunar:

| Seviye | Açıklama |
|:---|:---|
| `privileged` | Kısıtlama yok (sistem bileşenleri için) |
| `baseline` | Minimum kısıtlama |
| `restricted` | Root yasak, host yetkileri kapalı (en güvenli) |

```bash
# Namespace'i restricted modda kur
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

## 2.6 İmaj Güvenliği: Sadece İmzalı İmajlara İzin Ver

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-image-signature
    match:
      any:
      - resources:
          kinds: [Pod]
    verifyImages:
    - imageReferences:
      - "my-registry.example.com/*"
      attestors:
      - count: 1
        entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              <COSIGN_PUBLIC_KEY>
              -----END PUBLIC KEY-----
```

> [!TIP]
> `validationFailureAction: Audit` ile politikayı önce **gözlem modunda** çalıştırın. Raporları `kubectl get policyreport -A` ile inceleyin, ardından `Enforce`'a geçin.


# Pod Security Standards (PSS & PSA)

PodSecurityPolicy (PSP), Kubernetes 1.25'te tamamen kaldırıldı. Yerine gelen **Pod Security Standards (PSS)** ve bunu zorunlu kılan **Pod Security Admission (PSA)**, güvenlik politikalarını cluster seviyesinde yönetir.

---

## Neden PSP Kaldırıldı?

PSP karmaşıktı: RBAC ile birleşince anlaşılması zor davranışlar üretiyordu, hatalı yapılandırma kolaylaştı. PSA bu karmaşıklığı kaldırır — sadece üç güvenlik seviyesi, namespace annotation ile aktif edilir.

---

## Üç Güvenlik Profili

### 1. Privileged (Kısıtsız)

```
Her şeye izin verilir. Cluster yöneticileri için.
Kimler kullanır: kube-system, monitoring, CNI plugin'ler
```

### 2. Baseline (Temel Kısıtlamalar)

```
En yaygın privilege escalation vektörlerini engeller.
Kimler kullanır: Çoğu iş yükü için başlangıç noktası
Engeller:
  - HostNetwork, HostPID, HostIPC
  - Ayrıcalıklı container (privileged: true)
  - hostPath volume (güvenli olmayan yollar)
  - Tehlikeli capabilities (NET_RAW, SYS_ADMIN)
```

### 3. Restricted (En Sıkı)

```
Güvenlik best practice'lerini zorlar.
Kimler kullanır: Güvenlik kritik iş yükleri
Baseline'ın her şeyine ek olarak:
  - runAsNonRoot: true zorunlu
  - allowPrivilegeEscalation: false zorunlu
  - Sadece belirli volume türleri (configMap, emptyDir, projected, secret, downwardAPI, PVC)
  - seccompProfile: RuntimeDefault veya Localhost
  - capabilities: ALL drop edilmeli
```

---

## Pod Security Admission (PSA) — Aktifleştirme

```yaml
# Namespace'e annotation ekle — üç mod var:
# enforce: Kural ihlali → Pod reddedilir
# audit:   Kural ihlali → Log'a yazılır (pod çalışır)
# warn:    Kural ihlali → Kullanıcıya uyarı gösterilir (pod çalışır)

apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # Restricted profili zorla
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest

    # Audit için farklı profil
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest

    # Uyarı için
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

```bash
# Mevcut namespace'e PSA ekle
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

# PSA olmadan önce ne kadar pod etkileneceğini gör (dry-run)
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  --dry-run=server
```

---

## Restricted Profil ile Uyumlu Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: production
spec:
  # seccomp profili zorunlu (restricted)
  securityContext:
    seccompProfile:
      type: RuntimeDefault      # Varsayılan seccomp profili
    runAsNonRoot: true          # Root olarak çalışamazsın
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000

  containers:
  - name: app
    image: ghcr.io/company/app:v2
    securityContext:
      allowPrivilegeEscalation: false   # setuid/setgid yasak
      readOnlyRootFilesystem: true      # Root dosya sistemi salt okunur
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL                           # Tüm Linux capabilities kaldır
        # Gerekirse belirli capability ekle:
        # add: [NET_BIND_SERVICE]       # 1024 altı port için
    volumeMounts:
    - name: tmp
      mountPath: /tmp                   # Yazılabilir geçici alan

  volumes:
  - name: tmp
    emptyDir: {}                        # Restricted'ta izin verilen volume türü

  # HostNetwork, HostPID, HostIPC yasak (restricted)
  hostNetwork: false
  hostPID: false
  hostIPC: false
```

---

## Cluster Genelinde Varsayılan Profil

```yaml
# kube-apiserver flag'ı ile cluster-wide varsayılan
# /etc/kubernetes/manifests/kube-apiserver.yaml
- --admission-plugins=...,PodSecurity
- --feature-gates=...,PodSecurity=true

# AdmissionConfiguration ile varsayılan ayarlar
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults:
      enforce: baseline        # Varsayılan tüm namespace'ler için
      enforce-version: latest
      audit: restricted
      audit-version: latest
      warn: restricted
      warn-version: latest
    exemptions:
      # Bu namespace'ler PSA'dan muaf
      namespaces:
      - kube-system
      - monitoring
      - ingress-nginx
      - longhorn-system
      # Bu kullanıcılar PSA'dan muaf (cluster admin)
      usernames:
      - system:serviceaccount:kube-system:default
```

---

## Mevcut Namespace'i Değerlendirme

```bash
# Namespace'teki pod'lar hangi profille uyumlu?
kubectl label namespace my-namespace \
  pod-security.kubernetes.io/enforce=restricted \
  --dry-run=server 2>&1 | grep "Warning"

# Tüm namespace'leri tara
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== $ns ==="
  kubectl label namespace $ns \
    pod-security.kubernetes.io/enforce=restricted \
    --dry-run=server 2>&1 | grep -i "warning\|error" || echo "✅ Uyumlu"
done
```

---

## Kyverno ile Ek Politikalar

PSA temel korumaları sağlar; Kyverno daha ince politikalar için kullanılır:

```yaml
# Sadece approved registries'den image çekmeye izin ver
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-registry
    match:
      resources:
        kinds: [Pod]
    validate:
      message: "Sadece ghcr.io/company ve registry.company.com'dan image çekilebilir"
      pattern:
        spec:
          containers:
          - image: "ghcr.io/company/* | registry.company.com/*"
```

---

## Geçiş Stratejisi (PSP → PSA)

```bash
# Adım 1: Audit modda başla (pod'lar çalışmaya devam eder)
kubectl label namespace production \
  pod-security.kubernetes.io/audit=restricted

# Adım 2: Audit loglarını kontrol et
kubectl get events -n production | grep "PodSecurity"

# Adım 3: Pod'ları uyumlu hale getir (securityContext düzelt)
# Adım 4: Warn moduna geç
kubectl label namespace production \
  pod-security.kubernetes.io/warn=restricted

# Adım 5: Sorun kalmadığında enforce et
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted

# Adım 6: PSP'leri kaldır (K8s 1.25+ zaten yok)
kubectl delete psp --all
```

> [!TIP]
> **Restricted'tan başlama:** Yeni namespace'ler için enforce=restricted ile başlayın. Mevcut namespace'ler için audit → warn → enforce sıralamasıyla geçiş yapın. `readOnlyRootFilesystem: true` en çok soruna yol açan ayardır — uygulamaların nereye yazdığını kontrol edin.

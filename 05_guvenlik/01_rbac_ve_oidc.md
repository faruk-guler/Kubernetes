# RBAC ve OIDC Kimlik Doğrulama

## 1.1 RBAC Nedir?

**Role-Based Access Control (RBAC)**, kullanıcılara ve servislere "en az yetki" prensibine göre izin verir.

### Temel Kavramlar

| Kaynak | Kapsam | Açıklama |
|:---|:---:|:---|
| `Role` | Namespace | Belirli bir namespace içindeki kaynaklara (pod, configmap) erişim. |
| `ClusterRole` | Cluster | Tüm cluster genelindeki kaynaklara (node, namespace) erişim. |
| `RoleBinding` | Namespace | `Role` veya `ClusterRole`'ü bir namespace içinde kullanıcıya bağlar. |
| `ClusterRoleBinding` | Cluster | `ClusterRole`'ü tüm cluster genelinde yetkilendirir. |

---

### 1.1.1 RBAC Mantığı: User vs Service Account (1w2.net Detay)
Kubernetes'te iki tür "varlık" (subject) bulunur:
1.  **Users:** Cluster dışındaki gerçek kişiler (admin, developer). Kubernetes bunları `User` olarak tanır ancak yönetmez (OIDC/Sertifika gereklidir).
2.  **Service Accounts (SA):** Pod'lar içindeki process'lerin (Örn: Monitoring ajanı) API Server ile konuşması için kullanılır. Namespace bazlıdır.

## 1.2 Temel RBAC Örnekleri

### Pod Okuma Rolü

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: production
  name: pod-reader
rules:
- apiGroups: [""]                    # "" = core API grubu
  resources: ["pods", "pods/log"]
  verbs: ["get", "watch", "list"]
---
# Cluster-wide Node İzleme Rolü
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: production
subjects:
- kind: User
  name: developer@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ServiceAccount için RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deploy-bot
  namespace: production
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-manager
  namespace: production
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-bot-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: deploy-bot
  namespace: production
roleRef:
  kind: Role
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io

---

### 💡 ServiceAccount Güvenliği (Black Belt)
Her pod varsayılan olarak `default` service account'u kullanır ve token'ını `/var/run/secrets/kubernetes.io/serviceaccount` dizinine mount eder. Güvenlik için:
1.  **Token Mount Kapatma:** Eğer pod API Server ile konuşmayacaksa token'ı kapatın.
    ```yaml
    spec:
      automountServiceAccountToken: false
    ```
2.  **Custom SA:** Her zaman uygulamaya özel bir ServiceAccount oluşturun; asla `default` SA'ya yetki vermeyin.
```

## 1.3 RBAC Doğrulama

```bash
# Bir kullanıcının yetkisini kontrol et
kubectl auth can-i create pods --as=developer@example.com -n production

# ServiceAccount yetkisi
kubectl auth can-i update deployments \
  --as=system:serviceaccount:production:deploy-bot -n production

# Tüm yetkileri listele
kubectl auth can-i --list --as=developer@example.com
```

## 1.4 OIDC ile Kurumsal Kimlik Doğrulama

2026'da bireysel `kubeconfig` yerine şirket kimlik sağlayıcılarından (Google Workspace, Okta, Keycloak) giriş yapılır.

### API Server OIDC Yapılandırması

```yaml
# kubeadm yapılandırması
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  extraArgs:
    oidc-issuer-url: "https://accounts.google.com"
    oidc-client-id: "k8s-prod-cluster"
    oidc-username-claim: "email"
    oidc-groups-claim: "groups"
```

### Dex ile OIDC Köprüsü

```bash
# Dex kurulumu (Helm)
helm repo add dex https://charts.dexidp.io
helm install dex dex/dex \
  --namespace dex \
  --create-namespace
```

> [!TIP]
> **Pinniped** aracı, hem OIDC hem de Active Directory üzerinden Kubernetes erişimi için CNCF'nin önerdiği çözümdür. `Dex + Pinniped` kombinasyonu 2026 standartlarında öne çıkmaktadır.

## 1.5 Audit Logging

Kimin ne yaptığını kaydetmek için:

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
- level: Metadata
  resources:
  - group: "apps"
    resources: ["deployments"]
- level: None
  verbs: ["get", "list", "watch"]
  resources:
  - group: ""
    resources: ["pods"]
```


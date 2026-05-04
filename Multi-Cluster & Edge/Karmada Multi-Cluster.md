# Çoklu Cluster Yönetimi — Karmada

## Neden Çoklu Cluster?

| Gerekçe | Açıklama |
|:---|:---|
| **Blast Radius** | Bir cluster bozulursa diğeri çalışmaya devam eder |
| **Latency** | Kullanıcıya en yakın bölgedeki cluster'dan hizmet |
| **Compliance** | Verinin ülke sınırları içinde kalması zorunluluğu |
| **Scale** | Tek cluster'ın kapasitesini aşan iş yükleri |

## Karmada ile Federasyon

2026'da cluster'ları tek tek yönetmek yerine, hepsini tek bir merkezden yönetmek için **Karmada** kullanılır.

```bash
# Karmada kurulumu
curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo bash
karmadactl init
```

**PropagationPolicy:**

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: web-app-policy
spec:
  resourceSelectors:
  - apiVersion: apps/v1
    kind: Deployment
    name: web-app
  placement:
    clusterAffinity:
      clusterNames:
      - cluster-europe
      - cluster-asia
    replicaScheduling:
      replicaSchedulingType: Divided      # Replica'ları böl
      replicaDivisionPreference: Weighted
      weightPreference:
        staticClusterWeight:
        - targetCluster:
            clusterNames: [cluster-europe]
          weight: 60                      # Avrupa: %60
        - targetCluster:
            clusterNames: [cluster-asia]
          weight: 40                      # Asya: %40
```

**OverridePolicy — Cluster'a Özgü Yapılandırma:**

```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: ClusterOverridePolicy
metadata:
  name: env-override
spec:
  resourceSelectors:
  - apiVersion: apps/v1
    kind: Deployment
    name: web-app
  overrideRules:
  - targetCluster:
      clusterNames: [cluster-europe]
    overriders:
      envs:
      - component: web
        operator: addIfAbsent
        envs:
        - name: REGION
          value: eu-west-1
```

## Submariner — Cross-Cluster Ağ

Farklı cluster'lardaki pod'ların birbirleriyle haberleşmesi için:

```bash
# Submariner broker kurulumu (merkezi cluster)
subctl deploy-broker

# Her cluster'ı join et
subctl join broker-info.subm --clusterid=cluster-europe
subctl join broker-info.subm --clusterid=cluster-asia
```

Özellikler:
- Cluster'lar arası IPsec/WireGuard tünelleri
- **ServiceExport/ServiceImport** ile servis keşfi
- Global DNS: `service.namespace.svc.clusterset.local`

```yaml
# Servisi diğer cluster'lardan erişilebilir yap
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: database-svc
  namespace: production
```

## Global Load Balancing

```yaml
# Karmada MultiClusterIngress yerine Gateway API kullanın
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: global-route
spec:
  parentRefs:
  - name: global-gateway
  rules:
  - backendRefs:
    - name: web-app-eu      # Europe cluster
      port: 80
      weight: 60
    - name: web-app-asia    # Asia cluster
      port: 80
      weight: 40
```

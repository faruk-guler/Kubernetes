# Network Policy

Kubernetes'te varsayılan olarak tüm pod'lar birbirleriyle konuşabilir. NetworkPolicy, bu trafiği namespace ve label bazında kısıtlar. Cilium ile L7 seviyesinde ek kontrol mümkündür.

---

## Temel Kavramlar

```
NetworkPolicy = Firewall kuralı (pod seviyesinde)
  podSelector  → Hangi pod'lara uygulanır?
  policyTypes  → Ingress (gelen) | Egress (giden) | İkisi
  ingress      → Gelen trafiğe izin ver
  egress       → Giden trafiğe izin ver

NOT: Policy eklenmemiş pod → tüm trafiğe açık
     Policy eklenmiş pod   → sadece izin verilen trafik geçer
```

---

## Default Deny (Tüm Trafiği Engelle)

```yaml
# Namespace'teki tüm pod'lara uygula — başlangıç noktası
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}           # Tüm pod'lar
  policyTypes:
  - Ingress
  - Egress
```

---

## Seçici İzinler

### Belirli Uygulamadan Gelen Trafiğe İzin Ver

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api              # api pod'larına uygula
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend     # Sadece frontend'den
    ports:
    - protocol: TCP
      port: 8080
```

### Farklı Namespace'ten Gelen Trafiğe İzin Ver

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app: prometheus     # monitoring namespace'inden sadece prometheus
    ports:
    - protocol: TCP
      port: 9090
```

### Egress — DNS + Belirli Servisler

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress
  egress:
  # DNS her zaman açık olmalı (yoksa pod'lar hiçbir yere bağlanamaz)
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53

  # Veritabanına izin ver
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432

  # Redis'e izin ver
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
```

---

## Gerçek Dünya Senaryosu — 3 Katmanlı Uygulama

```yaml
# Frontend → API izin ver
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - port: 3000
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - port: 8080
  - ports:              # DNS
    - port: 53
      protocol: UDP
---
# API → DB izin ver, frontend'den geleni kabul et
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: api
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - port: 5432
  - ports:
    - port: 53
      protocol: UDP
---
# Database → sadece API'dan geleni kabul et
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - port: 5432
```

---

## Test ve Sorun Giderme

```bash
# NetworkPolicy oluşturuldu mu?
kubectl get networkpolicy -n production

# Policy detayı
kubectl describe networkpolicy allow-frontend-to-api -n production

# Bağlantı testi — netshoot ile
kubectl run test --image=nicolaka/netshoot --rm -it -- \
  curl -v http://api-service.production.svc.cluster.local:8080

# Engellenen bağlantı testi
kubectl run test --image=nicolaka/netshoot -n staging --rm -it -- \
  curl --connect-timeout 3 http://api-service.production.svc.cluster.local

# Cilium ile flow izleme (hangi trafik engellendi?)
hubble observe --verdict DROPPED --namespace production
hubble observe --pod production/api-xxx --follow

# Policy simulator (Cilium)
kubectl -n kube-system exec ds/cilium -- \
  cilium policy trace \
  --src-k8s-pod production/frontend-xxx \
  --dst-k8s-pod production/api-xxx \
  --dport 8080 --protocol tcp
```

> [!IMPORTANT]
> NetworkPolicy eklerken **DNS egress'i (port 53 UDP/TCP) unutma**. Yoksa pod'lar hiçbir servis adını çözemez ve tamamen devre dışı kalır.

> [!TIP]
> Her namespace'e `default-deny-all` policy'siyle başla, sonra gerekli izinleri ekle. Aksi hâlde "neyi engellediğini" değil "neye izin verdiğini" takip edersin — bu çok daha güvenli.

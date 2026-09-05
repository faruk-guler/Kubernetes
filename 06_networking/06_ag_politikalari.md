# Ağ Politikaları (Network Policy)

Kubernetes'te varsayılan ağ davranışı **"varsayılan olarak açık (default-allow)"** modelidir; yani küme içindeki tüm podlar birbirleriyle ve dış dünya ile hiçbir kısıtlama olmaksızın doğrudan konuşabilir. Güvenlik ve yalıtım sağlamak amacıyla bu trafiği sınırlandırmak için **NetworkPolicy** kaynakları kullanılır.

---

## 1. Temel Kavramlar

Bir NetworkPolicy, pod düzeyinde çalışan sanal bir güvenlik duvarı (firewall) gibidir:

```text
NetworkPolicy Bileşenleri:
  ├── podSelector  ──► Kuralın hangi podlara uygulanacağını seçer (Seçici)
  ├── policyTypes  ──► Ingress (gelen trafik) veya Egress (giden trafik) yalıtımı
  ├── ingress      ──► Gelen trafik için izin verilen kaynaklar (from) ve portlar
  └── egress       ──► Giden trafik için izin verilen hedefler (to) ve portlar
```

> [!IMPORTANT]
> **Kritik Kural:** Bir pod üzerine hiçbir NetworkPolicy uygulanmamışsa, o pod her türlü trafiğe açıktır. Ancak podu seçen en az bir policy oluşturulduğu anda pod **yalıtılmış (isolated)** hale gelir ve sadece izin verilen (whitelist) trafik geçebilir.

---

## 2. Varsayılan Olarak Her Şeyi Engelleme (Default Deny)

Güvenli bir altyapı tasarımı için, her yeni namespace oluşturulduğunda ilk olarak tüm giriş ve çıkış trafiğini kapatan bir policy uygulanmalıdır:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

---

## 3. Seçici Trafik İzinleri (Whitelisting)

Trafiği engelledikten sonra, sadece meşru akışlara izin verilir.

### A. Belirli Bir Poddan Gelen Trafiğe İzin Verme (Ingress)

Sadece `app: frontend` etiketli podlardan port 8080'e gelen trafiği kabul eden policy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### B. Farklı Bir Namespace'ten Gelen Trafiğe İzin Verme

`staging` ad alanından (namespace) gelen trafiği kabul etmek için:

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: staging
```

### C. Giden Trafikte DNS İznini Unutmamak (Egress)

Bir poda Egress (giden) kısıtlaması getirdiğinizde, podun DNS sorgusu yapabilmesi için UDP/53 (CoreDNS) iznini eklemek **zorunludur**. Aksi halde pod hiçbir servisin adını çözemez:

```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
```

---

## 4. Test ve Teşhis (Troubleshooting)

Ağ politikalarının engelleme durumlarını test etmek ve izlemek için:

```bash
# 1. Namespace içindeki ağ politikalarını listeleyin
kubectl get networkpolicy -n production

# 2. Cilium CNI kullanıyorsanız hangi trafiğin engellendiğini Hubble ile izleyin
hubble observe --verdict DROPPED --namespace production

# 3. İki pod arasındaki kural geçişini simüle edin (Cilium CLI)
kubectl -n kube-system exec ds/cilium -- \
  cilium policy trace \
  --src-k8s-pod production/frontend-pod \
  --dst-k8s-pod production/billing-api-pod \
  --dport 8080 --protocol tcp
```

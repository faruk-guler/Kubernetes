# Ağ Politikaları (Network Policy)

Kubernetes'te varsayılan ağ davranışı **"varsayılan olarak açık (default-allow)"** modelidir; yani küme içindeki tüm podlar birbirleriyle ve dış dünya ile hiçbir kısıtlama olmaksızın doğrudan konuşabilir. Güvenlik ve yalıtım sağlamak amacıyla bu trafiği sınırlandırmak için **NetworkPolicy** kaynakları kullanılır.

---

## 1. Temel Kavramlar

Bir NetworkPolicy, pod düzeyinde çalışan sanal bir güvenlik duvarı (firewall) gibidir:

```
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

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ag_politikalari_manifest_1.yaml](../Manifests/05_networking/ag_politikalari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Seçici Trafik İzinleri (Whitelisting)

Trafiği engelledikten sonra, sadece meşru akışlara izin verilir.

### A. Belirli Bir Poddan Gelen Trafiğe İzin Verme (Ingress)

Sadece `app: frontend` etiketli podlardan port 8080'e gelen trafiği kabul eden policy:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ag_politikalari_manifest_2.yaml](../Manifests/05_networking/ag_politikalari_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

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

Bir poda Egress (giden) kısıtlaması getirdiğinizde, podun DNS sorgusu yapabilmesi için UDP/53 (CoreDNS) iznini eklemek **zorunludur**. Aksi halde pod hiçbir servisin adını çözemez.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ag_politikalari_manifest_3.yaml](../Manifests/05_networking/ag_politikalari_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

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

# 📖 Hizmetler (Service) ve Ingress

Kubernetes'te pod'lara istikrarlı bir ağ adresi kazandırmak ve trafiği yönetmek için servisler kullanılır.

---

## 3.1 Neden Servis (Service)?

Pod'lar geçicidir (ephemeral). Bir pod çöktüğünde veya güncellendiğinde IP adresi değişir. Servisler, bu değişken pod grubunun önüne sabit bir IP (ClusterIP) ve DNS adı koyarak kesintisiz iletişim sağlar.

---

## 3.2 Servis Türleri (Service Types)

Kubernetes'te erişim seviyesine göre 4 temel servis türü bulunur:

| Tür | Erişim Aralığı | Kullanım Amacı |
|:---|:---|:---|
| **ClusterIP** | Sadece Cluster İçi | Mikroservisler arası iletişim. (Varsayılan). |
| **NodePort** | Cluster Dışı (Statik Port) | Dışarıdan fiziksel IP + Port (30000-32767) ile erişim. |
| **LoadBalancer** | Cluster Dışı (Bulut SA) | Bulut sağlayıcı (AWS/GCP/Azure) veya MetalLB ile dış IP atama. |
| **ExternalName** | Kurumsal DNS Alias | Harici bir kaynağı (Örn: `prod.db.com`) CNAME olarak cluster içine alias ekler. Uygulama kodu değişmeden dış servise bağlanabilir. |

---

## 3.3 Servis Keşfi (Kubernetes DNS)
Kubernetes'te bir servis oluşturulduğunda, otomatik olarak bir DNS kaydı (CoreDNS) oluşturulur. Pod'lar birbirine IP adresi yerine bu DNS isimleriyle bağlanır.

### DNS Adresleme (FQDN) Mantığı:
Bir servise şu formatta ulaşabilirsiniz:
`<servis-adı>.<namespace>.svc.cluster.local`

**Örnek Senaryo (yyy Nugget):**
`production` namespace'inde bir `mysql-service` olduğunu varsayalım. Aynı veya farklı namespace'teki podlar şu şekilde bağlanır:
1.  **Aynı Namespace:** Sadece `mysql-service` yazarak bağlanabilirler.
2.  **Farklı Namespace:** `mysql-service.production` yazarak veya tam adı (FQDN) kullanarak bağlanabilirler.

---

---

## 3.3 Port Haritalama (IP & Port Mapping)

Bir servisin port yapılandırması şu şekildedir:

```yaml
kind: Service
spec:
  type: NodePort      # Erişim türü
  selector:
    app: backend-api  # Hangi pod'lara gideceğini seçer
  ports:
  - name: http
    port: 80          # Servisin iç IP-Portu (Service Port)
    targetPort: 8080  # Pod'un içindeki uygulama portu (Container Port)
    nodePort: 32000   # Node üzerinde dışarıdan erişim portu (Opsiyonel)
```

### 💡 Headless Service (ClusterIP: None)
Eğer Load Balancer istenmiyorsa ve doğrudan pod IP'lerine erişilmek isteniyorsa (Veritabanı cluster'ları için), `clusterIP: None` kullanılır. DNS sorgusu servis IP'si yerine doğrudan Pod IP listesini döner.

---

## 3.4 Ingress vs Gateway API (2026 Standartı)

- **Ingress:** Web trafiğini (L7) host ve path bazlı (Örn: `app.com/api`) yönlendiren geleneksel proxy katmanıdır.
- **Gateway API:** Ingress'in modern halidir. Role-based yetkilendirme, gelişmiş trafik yönetimi (Traffic Splitting) ve HTTP/3 desteği sunar.

> [!TIP]
> 2026'da projemiz **Gateway API** ve **Cilium eBPF** kullanmaktadır. Klasik Ingress yerine Gateway'i tercih edin.

---

## 3.5 Operasyonel Komutlar

```bash
# Servisleri listele
kubectl get svc -A

# Endpoint grubunu kontrol et (Hangi pod'lar servise bağlı?)
kubectl get endpoints my-service

# DNS çözümleme testi (Pod içinden)
kubectl exec -it <pod-adi> -- nslookup my-service.default.svc.cluster.local
```

---
*← [Gateway API](01_gateway_api.md) | [Ana Sayfa](../README.md)*

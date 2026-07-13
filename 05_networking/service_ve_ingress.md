# Servis ve Ingress Yönetimi (Service & Ingress)

Kubernetes'te podlar dinamik ve geçici nesnelerdir. Bu nedenle podlara doğrudan IP adresleri üzerinden erişmek sürdürülemez. Podlara sabit bir ağ kimliği kazandırmak ve dış dünyadan gelen istekleri içeriye yönlendirmek için **Service** ve **Ingress** kaynakları kullanılır.

---

## 1. Kubernetes Servis (Service) Türleri

Servisler, etiket seçicileri (label selectors) aracılığıyla eşleşen podların önünde duran sanal yük dengeleyicilerdir. Dört temel servis türü bulunur:

### A. ClusterIP (Varsayılan)

Sadece küme (cluster) içinden erişilebilen servis tipidir. Küme dışından gelen isteklere kapalıdır.

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [service_ve_ingress_manifest_2.yaml](../Manifests/05_networking/service_ve_ingress_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. NodePort

Her worker düğümün (node) dış IP adresi üzerinde belirli bir statik port (30000-32767 arası) açar. Dış dünyadan düğüm IP'si ve bu port kullanılarak podlara erişilebilir.

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 31200 # Manuel atama yapılabilir
```

### C. LoadBalancer

Bulut sağlayıcılarında (AWS, GCP, Azure vb.) veya şirket içi ortamlarda (MetalLB ile) harici bir yük dengeleyici (External Load Balancer) oluşturur. Dış dünyaya açık benzersiz bir statik IP adresi sağlar.

```yaml
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
```

### D. ExternalName

Küme içindeki podların, dış dünyadaki bir servise (Örn: harici AWS RDS veritabanı) küme içi DNS kullanarak erişmesini sağlayan bir CNAME kaydıdır.

```yaml
spec:
  type: ExternalName
  externalName: db.external-provider.com
```

---

## 2. Endpoint ve EndpointSlice Mekanizması

Kubernetes'te bir servis oluşturulduğunda, etiket seçicisine uyan tüm canlı podların IP'leri otomatik olarak izlenir ve **Endpoint** (veya büyük kümelerde daha performanslı olan **EndpointSlice**) nesnelerine yazılır:

```bash
# Servise bağlı pod IP listesini (endpoints) sorgulayın
kubectl get endpoints billing-api-service -n production

# Detaylı EndpointSlice durumunu inceleyin
kubectl get endpointslices -n production -l kubernetes.io/service-name=billing-api-service
```

*Not:* Eğer endpoints listesi `<none>` veya boş görünüyorsa, servis üzerindeki `spec.selector` tanımı ile podların üzerindeki `metadata.labels` tanımları uyuşmuyor demektir.

---

## 3. Ingress Controller ve HTTP/HTTPS Yönlendirme

Servisler (özellikle LoadBalancer tipi) katman 4 düzeyinde (TCP/UDP) çalışır. Web trafiğini host adı (domain) veya HTTP path bazlı yönlendirmek ve TLS (SSL) sertifikası sonlandırması yapmak için katman 7 (HTTP) düzeyinde çalışan **Ingress** kullanılır.

### Örnek Ingress Kaynağı

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [service_ve_ingress_manifest_1.yaml](../Manifests/05_networking/service_ve_ingress_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Servis Sorunlarını Giderme (Teşhis Adımları)

Ağ trafiği uygulamaya ulaşmadığında izlenecek en hızlı denetim listesi:

```bash
# 1. Servisin arkasında canlı podlar (endpoints) var mı?
kubectl get ep billing-api-service -n production

# 2. Podlar hazır mı (Readiness Probe'dan geçmiş mi)?
kubectl get pods -n production -l app=billing-api
# (READY kolonu 0/1 ise pod trafiği kabul etmiyor demektir)

# 3. Port Forwarding ile servise direkt tünel açıp test etme
kubectl port-forward svc/billing-api-service 8080:80 -n production
# Tarayıcıdan http://localhost:8080/healthz adresini kontrol edin
```

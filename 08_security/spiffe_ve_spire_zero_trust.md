# SPIFFE ve SPIRE ile Sıfır Güven (Zero-Trust) İş Yükü Kimliği

Kubernetes kümelerinde pod'lar arası güvenli iletişim genellikle IP tabanlı kurallar (NetworkPolicy) veya Kubernetes Service Account token'ları ile sağlanır. Ancak mikroservis mimarileri büyüdükçe şu kritik soru ortaya çıkar: *"Gelen istek gerçekten `payment-service`'ten mi geliyor, yoksa kimliği ele geçirilmiş başka bir servisten mi?"*

Bu sorunun sıfır güven (Zero-Trust) kurallarına göre çözümü **SPIFFE** ve onun referans uygulaması olan **SPIRE**'dır. SPIFFE/SPIRE, pod'lara statik şifreler yerine kriptografik olarak kanıtlanabilir, dinamik ve kısa ömürlü kimlikler sağlar.

---

## 1. Temel Kavramlar

SPIFFE ve SPIRE ekosistemini anlamak için üç temel kavramı bilmek gerekir:

* **SPIFFE (Secure Production Identity Framework for Everyone):** Dağıtık ortamlardaki iş yüklerine (workloads) kimlik atamak ve doğrulamak için geliştirilmiş açık kaynaklı bir standarttır. Her iş yükü, standarda uygun bir URI formatında kimlik alır:

    `spiffe://<trust-domain>/<path>`
    *Örnek:* `spiffe://company.com/ns/production/sa/payment-service`

* **SPIRE (SPIFFE Runtime Environment):** SPIFFE standartlarının referans uygulaması olan ve kimlik dağıtımından sorumlu çalışan yazılımdır.
* **SVID (SPIFFE Verifiable Identity Document):** İş yükünün kimliğini kanıtlayan kriptografik belgedir. İki tür SVID bulunur:
  * **X.509-SVID:** Güvenli mTLS (Karşılıklı TLS) bağlantıları kurmak için kullanılan sertifikalardır.
  * **JWT-SVID:** HTTP Authorization başlıklarında (headers) taşınan JSON Web Token'lardır.

---

## 2. SPIRE Mimarisi

SPIRE, bir kontrol düzlemi (Server) ve her sunucuda koşan ajanlardan (Agent) oluşur:

```
                      ┌─────────────────────────┐
                      │  SPIRE Server (HA)      │
                      │  - CA (Sertifika Yetk.) │
                      │  - Kimlik Kayıt Defteri │
                      └────────────┬────────────┘
                                   │
                                   │ (gRPC / TLS)
                                   ▼
                      ┌─────────────────────────┐
                      │  SPIRE Agent (DaemonSet)│
                      └────────────┬────────────┘
                                   │
                     (Unix Domain Socket / Pod API)
                                   ▼
                      ┌─────────────────────────┐
                      │ Workload Pod            │
                      │ - /run/spire/agent.sock │
                      └─────────────────────────┘
```

* **SPIRE Server:** Kimliklerin kaydedildiği veritabanıdır (Entry Registry). SVID'leri imzalamak için kök sertifika yetkilisidir (CA).
* **SPIRE Agent:** Her Kubernetes worker node'unda `DaemonSet` olarak çalışır. Node'un kimliğini doğrular ve o node üzerindeki pod'lara kimliklerini Unix Domain Socket üzerinden iletir.
* **Workload:** Pod içinde çalışan uygulamadır. Başlangıçta Unix soketinden (`agent.sock`) SVID'ini talep eder ve mTLS/JWT doğrulamalarında kullanır.

---

## 3. SPIRE Kurulumu (Helm)

SPIRE bileşenlerini kümenizde yüksek kullanılabilirlik (HA - High Availability) modunda kurmak için aşağıdaki adımlar izlenir:

```bash
# 1. SPIFFE Helm deposunu ekleyin
helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/
helm repo update

# 2. SPIRE kurulumunu yapın
helm install spire spiffe/spire \
  --namespace spire-system \
  --create-namespace \
  --set global.spiffe.trustDomain="company.com" \
  --set spire-server.replicaCount=3 \
  --set spire-server.persistence.enabled=true \
  --set spire-agent.socketPath=/run/spire/sockets/agent.sock
```

---

## 4. İş Yükü Kaydı (Workload Registration)

SPIRE Server'a hangi pod'un hangi kimliği (SPIFFE ID) alabileceğini bildirmemiz gerekir. Buna "Kayıt Girişi" (Registration Entry) denir.

```bash
# production namespace'inde api-service-account kullanan pod'a
# spiffe://company.com/production/api kimliğini tanımlayın:

kubectl exec -n spire-system spire-server-0 -- \
  spire-server entry create \
    -spiffeID spiffe://company.com/production/api \
    -parentID "spiffe://company.com/spire/agent/k8s_sat/production" \
    -selector k8s:ns:production \
    -selector k8s:sa:api-service-account \
    -ttl 3600

# Kayıtlı tüm girişleri listeleme
kubectl exec -n spire-system spire-server-0 -- \
  spire-server entry show
```

---

## 5. İş Yüklerinde SVID Alma (Kod Örnekleri)

Uygulamanızın SPIRE soketinden kimlik alabilmesi için yazılan basit entegrasyon örnekleri:

### Go Entegrasyonu

```go
package main

import (
 "context"
 "fmt"
 "log"

 "github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
 "github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
 ctx := context.Background()

 // SPIRE Agent soket adresi
 socketAddr := "unix:///run/spire/sockets/agent.sock"

 // Sokete bağlanacak istemciyi oluştur
 client, err := workloadapi.New(ctx, workloadapi.WithAddr(socketAddr))
 if err != nil {
  log.Fatalf("Soket bağlantı hatası: %v", err)
 }
 defer client.Close()

 // X.509 SVID (mTLS sertifikası) al
 svid, err := client.FetchX509SVID(ctx)
 if err != nil {
  log.Fatalf("SVID alınamadı: %v", err)
 }

 fmt.Printf("Başarıyla kimlik alındı: %s\n", svid.ID)

 // Alınan SVID ile mTLS sunucu konfigürasyonu
 _ = tlsconfig.MTLSServerConfig(svid, svid.TrustBundle, tlsconfig.AuthorizeAny())
}
```

### Python Entegrasyonu

```python
from pyspiffe.workloadapi import DefaultWorkloadApiClient

# SPIRE Agent soketine bağlan
client = DefaultWorkloadApiClient(addr="unix:///run/spire/sockets/agent.sock")

try:
    svid = client.fetch_x509_svid()
    print(f"Kriptografik Kimlik: {svid.spiffe_id}")
except Exception as e:
    print(f"Sertifika alınırken hata oluştu: {e}")
```

---

## 6. Kubernetes ile Entegrasyon: SPIFFE CSI Driver

Pod'ların Unix Domain Socket'ine erişebilmesi için varsayılan olarak `hostPath` mount yöntemi kullanılır. Ancak bu yöntem güvenlik açığı yaratabilir. Güvenli yaklaşım, soketi pod'a **SPIFFE CSI Driver** aracılığıyla bağlamaktır.

### CSI Sürücü Entegrasyonu ile Pod YAML Örneği

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [spiffe_ve_spire_zero_trust_manifest_1.yaml](../Manifests/07_security/spiffe_ve_spire_zero_trust_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

SPIFFE CSI sürücüsü, podun kimliğini doğrular ve pod içine sadece o pod'a ait güvenli Unix soketini bağlar.

---

## 7. Istio ve SPIRE Entegrasyonu

Kubernetes ortamlarında servis mesh (Istio) kullanıyorsanız, Istio'nun yerleşik sertifika yetkilisi (Citadel) yerine arka planda daha güvenli olan SPIRE'ı konumlandırabilirsiniz.

Istio'nun Envoy proxy'leri, sertifikaları (SVID) doğrudan SPIRE Agent üzerinden almak için Envoy SDS (Secret Discovery Service) özelliğini kullanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [spiffe_ve_spire_zero_trust_manifest_2.yaml](../Manifests/07_security/spiffe_ve_spire_zero_trust_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu yapılandırma ile Istio üzerindeki mTLS trafiği, SPIFFE/SPIRE tarafından sağlanan kriptografik kimliklerle tamamen şifrelenir ve kontrol edilir.

---

## 8. JWT-SVID Kullanımı (HTTP Kimlik Doğrulama)

Eğer mTLS yerine HTTP başlıkları üzerinden kimlik doğrulamak istiyorsanız JWT-SVID kullanabilirsiniz:

```bash
# Agent soketinden payment-service hedefli bir JWT token talep etme:
TOKEN=$(kubectl exec -n production api-pod -- \
  /opt/spire/bin/spire-agent api fetch jwt \
  -audience spiffe://company.com/production/payment \
  -socketPath /run/spire/sockets/agent.sock)

# Alınan token ile HTTP isteği gönderme:
curl -H "Authorization: Bearer $TOKEN" \
  https://payment-service/api/v1/pay
```

---

## 9. Doğrulama ve Sorun Giderme

SPIRE kurulumunu ve pod'ların durumunu test etmek için şu komutlar kullanılır:

```bash
# 1. SPIRE Agent sağlık durumunu kontrol etme
kubectl exec -n spire-system -l app=spire-agent -- \
  spire-agent healthcheck -socketPath /run/spire/sockets/agent.sock

# 2. Bir podun SVID sertifikasını manuel olarak çekip sorgulama
kubectl exec -n production billing-service -- \
  /opt/spire/bin/spire-agent api fetch x509 \
  -socketPath /run/spire/sockets/agent.sock

# 3. SPIRE Server Kök Güven Raporunu (Trust Bundle) görüntüleme
kubectl exec -n spire-system spire-server-0 -- \
  spire-server bundle show
```

> [!NOTE]
> **Kubernetes Service Account Token vs. SPIRE SVID:**
> Kubernetes Service Account token'ları etcd üzerinde statik olarak kalabilir ve sızdırıldığında uzun süre geçerli olabilir. SPIRE SVID'leri ise tamamen hafızada (tmpfs) tutulur, 1 saat gibi çok kısa sürelerde otomatik olarak yenilenir ve doğrudan kernel seviyesindeki kimlik denetimleri (UID/GID) ile ilişkilendirilir.

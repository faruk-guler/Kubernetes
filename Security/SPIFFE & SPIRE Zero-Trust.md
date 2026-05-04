# SPIFFE & SPIRE — Zero-Trust Workload Identity

Kubernetes'te pod'lar arası güven nasıl kurulur? "Bu istek gerçekten payment-service'ten mi geliyor?" sorusunun cevabı SPIFFE/SPIRE'dir. Servis hesabı token'larının ötesinde, kriptografik olarak kanıtlanmış kimlik sağlar.

---

## Temel Kavramlar

```
SPIFFE (Secure Production Identity Framework For Everyone):
  → Workload kimlik standardı
  → Her workload'a URI formatında kimlik: spiffe://trust-domain/path

SPIRE (SPIFFE Runtime Environment):
  → SPIFFE'in referans implementasyonu
  → X.509 sertifika veya JWT SVID üretir

SVID (SPIFFE Verifiable Identity Document):
  → Workload'un kimlik belgesi
  → X.509-SVID: mTLS için
  → JWT-SVID: HTTP Authorization header için

Örnek: spiffe://company.com/ns/production/sa/payment-service
```

---

## Mimari

```
SPIRE Server (Control Plane)
  └── Entry Registry: "production namespace, app=api → bu kimliği ver"
  └── CA: SVID imzalar

SPIRE Agent (Her Node'da DaemonSet)
  └── Node'u Server'a doğrular
  └── Pod'a SVID dağıtır (Unix socket üzerinden)

Workload
  └── /run/spire/sockets/agent.sock → SVID al
  └── mTLS bağlantısında X.509 SVID kullan
```

---

## SPIRE Kurulum (Helm)

```bash
helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/

helm install spire spiffe/spire \
  --namespace spire-system \
  --create-namespace \
  --set global.spiffe.trustDomain="company.com" \
  --set spire-server.replicaCount=3 \           # HA
  --set spire-server.persistence.enabled=true \
  --set spire-agent.socketPath=/run/spire/sockets/agent.sock
```

---

## Workload Registration

```bash
# SPIRE'ye: "production namespace'inde app=api label'ına sahip pod'lara
#            spiffe://company.com/production/api kimliği ver"

kubectl exec -n spire-system spire-server-0 -- \
  spire-server entry create \
    -spiffeID spiffe://company.com/production/api \
    -parentID "spiffe://company.com/spire/agent/k8s_sat/production/$(kubectl get node -o jsonpath='{.items[0].metadata.name}')" \
    -selector k8s:ns:production \
    -selector k8s:sa:api-service-account \
    -ttl 3600

# Kayıtlı kimlikleri listele
kubectl exec -n spire-system spire-server-0 -- \
  spire-server entry show
```

---

## Workload'da SVID Alma

```go
// Go: SPIFFE workload API ile SVID al
import "github.com/spiffe/go-spiffe/v2/workloadapi"

ctx := context.Background()
client, _ := workloadapi.New(ctx,
  workloadapi.WithAddr("unix:///run/spire/sockets/agent.sock"))

// X.509 SVID al (mTLS için)
svid, _ := client.FetchX509SVID(ctx)
fmt.Println(svid.ID)  // spiffe://company.com/production/api

// TLS config oluştur
tlsConfig := tlsconfig.MTLSServerConfig(svid, svid.TrustBundle, tlsconfig.AuthorizeAny())
```

```python
# Python
from pyspiffe.workloadapi import DefaultWorkloadApiClient

client = DefaultWorkloadApiClient(addr="unix:///run/spire/sockets/agent.sock")
svid = client.fetch_x509_svid()
print(svid.spiffe_id)
```

---

## Kubernetes ile Entegrasyon (SPIFFE CSI Driver)

```yaml
# Pod'a SVID socket otomatik mount
apiVersion: v1
kind: Pod
metadata:
  name: api-pod
  namespace: production
spec:
  containers:
  - name: api
    image: company/api:v1.0
    volumeMounts:
    - name: spiffe-workload-api
      mountPath: /run/spire/sockets
      readOnly: true
  volumes:
  - name: spiffe-workload-api
    csi:
      driver: "csi.spiffe.io"
      readOnly: true
```

---

## Istio + SPIRE (Production Entegrasyonu)

```yaml
# Istio'nun SPIRE'dan SVID alması
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    defaultConfig:
      proxyMetadata:
        PROXY_CONFIG_XDS_AGENT: "true"
  values:
    global:
      caAddress: "spire-server.spire-system:8081"
    pilot:
      env:
        ENABLE_CA_SERVER: "false"
```

---

## JWT-SVID (HTTP Auth için)

```bash
# Workload'dan JWT SVID al
curl --unix-socket /run/spire/sockets/agent.sock \
  http://localhost/svid.json

# Başka servise JWT ile istek at
TOKEN=$(spiffe-helper fetch-jwt \
  --audience spiffe://company.com/production/payment)

curl -H "Authorization: Bearer $TOKEN" \
  https://payment-service/api/charge
```

---

## Doğrulama

```bash
# Agent sağlık kontrolü
kubectl exec -n spire-system -l app=spire-agent -- \
  spire-agent healthcheck

# Workload'un SVID'ini doğrula
kubectl exec -n production api-pod -- \
  /opt/spire/bin/spire-agent api fetch x509 \
  -socketPath /run/spire/sockets/agent.sock

# Server bundle (trust bundle) al
kubectl exec -n spire-system spire-server-0 -- \
  spire-server bundle show
```

> [!TIP]
> SPIFFE/SPIRE, service mesh olmadan mTLS sağlayan en temiz çözümdür. Istio/Linkerd ile birlikte kullanıldığında güven hiyerarşisi çok daha sağlam olur.

> [!NOTE]
> Kubernetes Service Account token'larıyla SPIRE arasındaki fark: SVID'ler kısa ömürlüdür (1 saat), otomatik döndürülür ve kriptografik zincirle doğrulanır. SA token'ları ise statik ve uzun ömürlü olabilir.

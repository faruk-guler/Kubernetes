# SPIFFE & SPIRE: Sıfır Güven (Zero-Trust) Workload Kimliği

Geleneksel güvenlik modellerinde "Aynı ağ (VPC) içindeysen veya bu IP bloğundaysan sana güvenirim" mantığı vardır (Network tabanlı güvenlik). **Zero Trust** felsefesinde ise IP adreslerine, ağlara veya token'lara (ServiceAccount) körü körüne güvenilmez. Uygulamanın (Pod) matematiksel (kriptografik) bir kimliği olmak zorundadır.

---

## 5.1 SPIFFE ve SPIRE Nedir?

- **SPIFFE** (Secure Production Identity Framework for Everyone): Uygulamaların birbirleriyle konuşurken mTLS (Mutual TLS) kurabilmesi için nasıl bir X.509 sertifikasyon standartı olması gerektiğini belirten bir manifestodur.
- **SPIRE** (SPIFFE Runtime Environment): Bu sertifikaları Kubernetes ortamında (Workload API) Dağıtan, Yöneten ve Döndüren (Rotate) yazılımın kendisidir.

**Temel Kural:** Frontend uygulamasının (Pod) bir SPIFFE ID'si vardır: `spiffe://sirketim.com/ns/frontend/sa/default`. Backend ona gelen isteği sadece bu ID'ye sahip X.509 sertifikasını görürse kabul eder. Parola yoktur!

---

## 5.2 Neden Kubernetes ServiceAccount Yetmiyor?

Kubernetes ServiceAccount bir JWT Bearer token dağıtır. Ancak JWT Token çalınabilir. Diyelim ki token bir saldırgan tarafından dışarı sızdırıldı. Saldırgan o token ile dış bir makineden API sunucusuna istek atabilir.

**SPIFFE ise kriptografiktir:** Sertifikanın Private Key'i asla sistemin hafızasından dışarı (Pod'dan) çıkmaz, ağ üzerinde gönderilmez. Bu sayede Replay Attack / Token Leakage önlenir. Istio Service Mesh, zaten arka planda SPIFFE standardını kullanır!

---

## 5.3 SPIRE Kubernetes Entegrasyonu

SPIRE genelde iki parçadan oluşur:
1. **SPIRE Server:** Kök sertifika otoriteliğini (Root CA) üstlenen merkez.
2. **SPIRE Agent (DaemonSet):** Her Kubernetes Node'unda çalışır ve Node'daki Pod'ların kimliğini onaylayıp Server'dan Sertifika alır. Pod ile Linux UNIX Domain Socket üzerinden haberleşir.

```bash
# Örnek Helm ile kurulum (Official spire-helm chart)
helm repo add spiffe https://spiffe.github.io/helm-charts-hardened/
helm install my-spire spiffe/spire -n spiffe-system --create-namespace
```

---

## 5.4 CSI Driver ile Kimlik Alma

2026 standartlarında Container'ın içine sertifika basmak için `SPIFFE CSI Driver` Volume olarak eklenir. Pod başlatıldığında, SPIRE Agent bu klasörün içine güncel TLS sertifika zincirini koyar.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secured-frontend
spec:
  containers:
  - name: my-app
    image: my-app:latest
    volumeMounts:
    - name: spiffe-workload-api
      mountPath: /spiffe-workload-api
      readOnly: true
  volumes:
  - name: spiffe-workload-api
    csi:
      driver: "csi.spiffe.io"    # SPIRE CSI tarafından sağlanır
      readOnly: true
```

Tebrikler! Kodunuz `/spiffe-workload-api/sockets.sock` yolunu okuduğu an, şirketinizdeki (veya diğer kıtalardaki multi-cluster) tüm backend sistemleriyle kimlik doğrulamalı (mTLS) konuşabilir. 

> [!IMPORTANT]
> SPIRE, çoklu ortam entegrasyonu (Federation) yapar. Yani AWS EKS üzerindeki bir Pod ile, on-premise veri merkezinizdeki bir Bash Script (SPIRE Agent üzerinden) hiçbir Secret ve Parola takası yapmadan, Zero-Trust üzerinden haberleşebilir.

---
*← [Ana Sayfa](../README.md)*

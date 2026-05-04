# CIS Kubernetes Benchmark

CIS (Center for Internet Security) Benchmark, Kubernetes cluster'larının güvenlik yapılandırması için dünya genelinde kabul görmüş referans standarttır. Bağımsız denetçiler ve otomasyon araçları aracılığıyla uyumluluk seviyesi ölçülür.

## Benchmark Hakkında

| Bilgi | Detay |
|:---|:---|
| **Geçerli sürüm** | CIS Kubernetes Benchmark v1.8 (2024) |
| **Hedef platform** | Self-managed Kubernetes (kubeadm / RKE2) |
| **Toplam kontrol** | 90+ güvenlik kontrolü |
| **Kategoriler** | Control Plane, etcd, Worker Node, Politikalar |

### 📄 Referans Belgeler

- [CIS Kubernetes Benchmark (Resmi)](https://www.cisecurity.org/benchmark/kubernetes)
- [Azure AKS CIS Kılavuzu](https://learn.microsoft.com/en-us/azure/aks/cis-kubernetes)
- [Benchmark PDF (v1.24)](../references/CIS%20Kubernetes%201.24%20Benchmark%20v1.0.0%20PDF.pdf)

---

## Kontrol Kategorileri

### 1. Control Plane — API Server

| Kontrol | Açıklama | Seviye |
|:---|:---|:---:|
| 1.2.1 | `--anonymous-auth=false` — anonim erişim kapalı | Kritik |
| 1.2.7 | `--authorization-mode=Node,RBAC` — RBAC zorunlu | Kritik |
| 1.2.22 | `--audit-log-path` yapılandırılmış | Yüksek |
| 1.2.31 | `--tls-min-version=VersionTLS12` | Yüksek |
| 1.2.34 | `--encryption-provider-config` (etcd şifreleme) | Yüksek |

### 2. etcd Güvenliği

| Kontrol | Açıklama |
|:---|:---|
| 2.1 | etcd erişimi TLS ile şifrelenmiş mi? |
| 2.2 | `--client-cert-auth=true` ayarlı mı? |
| 2.3 | etcd peer iletişimi şifreli mi? |

### 3. Worker Node — kubelet

| Kontrol | Açıklama |
|:---|:---|
| 4.2.1 | `--anonymous-auth=false` |
| 4.2.2 | `--authorization-mode=Webhook` |
| 4.2.6 | Read-only port (10255) kapalı |
| 4.2.10 | `--rotate-certificates=true` |

---

## kube-bench ile Otomatik Tarama

[kube-bench](https://github.com/aquasecurity/kube-bench), CIS kontrollerini cluster üzerinde otomatik çalıştıran açık kaynaklı Aqua Security aracıdır.

### Kubernetes Job olarak Çalıştırma

```bash
# Cluster üzerinde kube-bench job'u başlat
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# Tamamlanmasını bekle
kubectl wait --for=condition=complete job/kube-bench --timeout=60s

# Sonuçları oku
kubectl logs job/kube-bench
```

### Örnek Çıktı Yorumlama

```
[PASS] 1.1.1 API server pod spec dosya izinleri 644 veya daha kısıtlayıcı
[FAIL] 1.2.1 --anonymous-auth parametresi false olarak ayarlanmamış
[WARN] 1.2.16 Audit log boyut sınırı ayarlanmamış
[INFO] 1.2.17 Audit log yedekleme sayısı: varsayılan
```

> [!TIP]
> `[FAIL]` durumları mutlaka düzeltilmeli; `[WARN]` durumları ise ortam gereksinimlerine göre değerlendirilebilir.

### Binary ile Doğrudan Çalıştırma

```bash
# Master node kontrolü
./kube-bench run --targets master

# Worker node kontrolü
./kube-bench run --targets node

# etcd kontrolü
./kube-bench run --targets etcd
```

---

## Trivy ile Cluster Tarama

[Trivy](https://aquasecurity.github.io/trivy/), yanlış yapılandırmaları (misconfiguration) CIS standartlarına göre tarayabilir.

```bash
# Cluster geneli özet rapor
trivy k8s --report summary cluster

# Belirli namespace
trivy k8s --report summary -n production

# Tüm yanlış yapılandırmaları göster
trivy k8s --report all --misconfig cluster

# JSON çıktısı al
trivy k8s --format json -o report.json cluster
```

---

## Kritik `kube-apiserver` Parametreleri

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --anonymous-auth=false                              # CIS 1.2.1
    - --authorization-mode=Node,RBAC                     # CIS 1.2.7
    - --audit-log-path=/var/log/kubernetes/audit.log     # CIS 1.2.22
    - --audit-log-maxage=30                              # CIS 1.2.23
    - --audit-log-maxbackup=10                           # CIS 1.2.24
    - --audit-log-maxsize=100                            # CIS 1.2.25
    - --encryption-provider-config=/etc/kubernetes/enc.yaml  # CIS 1.2.34
    - --tls-min-version=VersionTLS12                     # CIS 1.2.31
```

---

## Hızlı Uyumluluk Kontrol Listesi

- [ ] `kube-bench` çalıştırıldı ve `[FAIL]` kalmadı
- [ ] API Server `--anonymous-auth=false` yapılandırıldı
- [ ] etcd at-rest şifrelemesi aktif
- [ ] Audit logging açık ve log rotasyonu tanımlandı
- [ ] kubelet read-only port (10255) kapalı
- [ ] TLS minimum sürümü v1.2 olarak ayarlandı

> [!NOTE]
> CIS Benchmark %100 uyumu tüm ortamlar için zorunlu değildir. Bazı kontroller kurumsal gereksinimlerinize göre istisna tutulabilir. `kube-bench` çıktısında `[WARN]` seviyesindekiler tavsiye niteliğindedir.

---

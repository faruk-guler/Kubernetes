# Kata Containers & gVisor — VM Düzeyinde İzolasyon

Standart container izolasyonu Linux namespace ve cgroup'lara dayanır — hızlıdır ama aynı kernel'ı paylaşır. Çok kiracılı (multi-tenant) veya güvenlik kritik ortamlarda bu yeterli değildir. **Kata Containers** ve **gVisor** her container'ı bir VM izolasyon sınırı içine alır.

---

## İzolasyon Katmanları Karşılaştırması

```
Geleneksel Container:
  App → Container Runtime (runc) → Linux Kernel (paylaşımlı)
  Risk: Kernel exploit → tüm node'u etkiler

Kata Containers:
  App → Container Runtime → MicroVM (QEMU/Firecracker) → Host Kernel
  Her pod kendi miniature kernel'ına sahip

gVisor (runsc):
  App → Container Runtime → gVisor Kernel (Go ile yazılmış user-space kernel) → Host Kernel
  Syscall'lar gVisor tarafından intercept edilir
```

---

## RuntimeClass CRD

Kubernetes, hangi container runtime kullanılacağını `RuntimeClass` ile belirler:

```yaml
# Kata Containers RuntimeClass
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-qemu
handler: kata-qemu    # containerd handler adıyla eşleşmeli
overhead:
  podFixed:
    cpu: "250m"       # VM overhead — fatura edilmeli
    memory: "160Mi"
scheduling:
  nodeSelector:
    kata-containers: "true"    # Kata kurulu node'lar

---
# gVisor RuntimeClass
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
scheduling:
  nodeSelector:
    gvisor: "true"
```

### Pod'da RuntimeClass Kullanımı

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-workload
  namespace: untrusted-tenants
spec:
  runtimeClassName: kata-qemu    # veya gvisor
  containers:
  - name: app
    image: ghcr.io/company/api:v2.1.0
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
```

---

## Kata Containers Kurulumu

```bash
# containerd için kata handler yapılandır
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu]
  runtime_type = "io.containerd.kata-containers.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu.options]
  ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration-qemu.toml"

# containerd'yi yeniden başlat
systemctl restart containerd

# Kata binary kurulumu (node üzerinde)
curl -LO https://github.com/kata-containers/kata-containers/releases/latest/download/kata-static-3.x.x-amd64.tar.xz
tar -xvf kata-static-*.tar.xz -C /opt/kata

# RuntimeClass oluştur
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-qemu
handler: kata-qemu
overhead:
  podFixed:
    cpu: "250m"
    memory: "160Mi"
EOF
```

### Firecracker ile Kata (AWS/Baremetal)

```toml
# /opt/kata/share/defaults/kata-containers/configuration-fc.toml
[hypervisor.firecracker]
  path = "/opt/kata/bin/firecracker"
  kernel = "/opt/kata/share/kata-containers/vmlinux.container"
  image = "/opt/kata/share/kata-containers/kata-containers.img"
  default_vcpus = 1
  default_memory = 128    # MB
```

---

## gVisor Kurulumu

```bash
# gVisor (runsc) kurulumu — node üzerinde
curl -fsSL https://gvisor.dev/archive.key | gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | tee /etc/apt/sources.list.d/gvisor.list
apt-get update && apt-get install -y runsc

# containerd yapılandır
runsc install    # Otomatik containerd konfigürasyonu yapar

systemctl restart containerd

# RuntimeClass oluştur
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
EOF

# Test
kubectl run gvisor-test --image=nginx:1.27 \
  --overrides='{"spec":{"runtimeClassName":"gvisor"}}' \
  --rm -it --restart=Never -- uname -r
# Çıktı: 4.4.0 (gVisor'un fake kernel versiyonu)
```

---

## Kata vs gVisor Karşılaştırması

| Kriter | Kata Containers | gVisor |
|:-------|:---------------|:-------|
| **İzolasyon** | Gerçek VM (hypervisor) | User-space kernel (ptrace/KVM) |
| **Overhead** | ~150-250ms başlatma | ~20-50ms başlatma |
| **Bellek overhead** | ~100-200 MB/pod | ~15-50 MB/pod |
| **Syscall uyumluluk** | Tam (Linux uyumlu) | Kısmi (~250 syscall destekli) |
| **GPU desteği** | Sınırlı | Yok |
| **En iyi kullanım** | SaaS multi-tenant, yüksek güvensizlik | CI runner, genel isolation |
| **AWS Firecracker** | ✅ Evet | ❌ Hayır |

---

## Kyverno ile Zorunlu RuntimeClass

Belirli namespace'lerde güvenli runtime zorunlu kılmak:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-secure-runtime
spec:
  validationFailureAction: Enforce
  rules:
  - name: require-runtimeclass
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: [untrusted-tenants, saas-customers]
    validate:
      message: "Bu namespace'de kata-qemu veya gvisor runtimeClassName zorunludur"
      pattern:
        spec:
          runtimeClassName: "kata-qemu | gvisor"
```

---

## Ne Zaman Kullanılır?

```
✅ Kata Containers:
   - SaaS platformu (birden fazla müşteri aynı cluster)
   - CI/CD runner'ları (arbitrary kod çalıştırma)
   - Untrusted workload çalıştıran fintech/healthtech

✅ gVisor:
   - Genel güvenlik katmanı ekleme (overhead tolere edilebiliyorsa)
   - Google Cloud Run, GKE Sandbox — production kanıtlı
   - Dev/staging ortamı izolasyonu

❌ Her ikisi de uygun değil:
   - GPU workload (AI/ML training)
   - Yüksek I/O gerektiren uygulamalar (DB, NVMe)
   - Düşük latency gerektiren real-time sistemler
```

> [!IMPORTANT]
> Kata/gVisor, namespace + seccomp + AppArmor'ın **yerine** değil, **üstüne** eklenen bir katmandır. Defense in depth: hem namespace izolasyonu HEM DE VM izolasyonu birlikte kullanın.

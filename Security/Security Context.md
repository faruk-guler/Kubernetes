# Security Context

Security Context, pod ve container seviyesinde Linux güvenlik ayarlarını tanımlar. Hangi kullanıcıyla çalışılacağı, dosya sisteminin salt okunur olup olmayacağı, hangi Linux capability'lerin aktif olduğu burada belirlenir. 2026'da CIS Benchmark ve Pod Security Standards bu ayarları zorunlu kılar.

---

## Neden Önemli?

```
Varsayılan container davranışı (securityContext yok):
  ❌ Root kullanıcısı (UID 0) ile çalışır
  ❌ Yazılabilir root filesystem
  ❌ Tüm Linux capability'leri aktif
  ❌ Syscall kısıtlaması yok
  ❌ Host namespace'e erişim mümkün

Güvenli container:
  ✅ Non-root kullanıcı (UID 1000+)
  ✅ Read-only root filesystem
  ✅ Sadece gerekli capability'ler
  ✅ Seccomp profili aktif
  ✅ Privilege escalation yasak
```

---

## Pod vs Container Seviyesi

```yaml
apiVersion: v1
kind: Pod
spec:
  # Pod seviyesi — tüm container'lara uygulanır
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000              # Volume mount owner group
    seccompProfile:
      type: RuntimeDefault     # containerd/runc varsayılan seccomp profili

  containers:
  - name: app
    # Container seviyesi — pod seviyesini override eder
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL                  # Tüm capability'leri kaldır
        add:
        - NET_BIND_SERVICE     # Sadece 1024 altı porta bind için
```

---

## Tam Üretim Örneği

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
spec:
  template:
    spec:
      # Pod seviyesi güvenlik
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001        # Uygulama'nın kendi UID'si
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault

      containers:
      - name: api
        image: company/api:v1.2.0
        securityContext:
          allowPrivilegeEscalation: false   # sudo yasak
          readOnlyRootFilesystem: true      # Dosya sistemi salt okunur
          capabilities:
            drop:
            - ALL

        # Read-only filesystem varsa yazılabilir geçici alan gerekebilir
        volumeMounts:
        - name: tmp-dir
          mountPath: /tmp
        - name: cache-dir
          mountPath: /app/cache

      volumes:
      - name: tmp-dir
        emptyDir: {}
      - name: cache-dir
        emptyDir:
          sizeLimit: 256Mi
```

---

## Linux Capabilities

```yaml
# Capability'ler — Docker'ın varsayılan verdiği bazıları:
# CAP_CHOWN, CAP_DAC_OVERRIDE, CAP_FOWNER, CAP_SETUID, CAP_SETGID
# CAP_NET_RAW, CAP_NET_BIND_SERVICE ...

# Güvenli yaklaşım: Hepsini kaldır, sadece gerekeni ekle
capabilities:
  drop:
  - ALL
  add:
  - NET_BIND_SERVICE    # 80, 443 gibi 1024 altı portlar
  # - CHOWN             # Dosya sahipliği değiştirme (nadiren)
  # - SYS_PTRACE        # Debug tools (sadece dev, prod'da değil)
```

```bash
# Bir process'in capability'lerini görüntüle (pod içinde)
cat /proc/1/status | grep Cap
# CapPrm: 0000000000000400  → sadece NET_BIND_SERVICE

# Decode et
capsh --decode=0000000000000400
# 0x0000000000000400=cap_net_bind_service
```

---

## Seccomp Profili

```yaml
# RuntimeDefault — container runtime'ın varsayılan profili (önerilen)
seccompProfile:
  type: RuntimeDefault

# Localhost — özel profil (ileri seviye)
seccompProfile:
  type: Localhost
  localhostProfile: profiles/audit.json

# Unconfined — profil yok (güvensiz, production'da kullanma)
seccompProfile:
  type: Unconfined
```

```json
# Örnek özel seccomp profili (/var/lib/kubelet/seccomp/profiles/app.json)
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": ["read", "write", "open", "close", "stat", "fstat",
                "mmap", "mprotect", "munmap", "brk", "rt_sigaction",
                "rt_sigprocmask", "ioctl", "access", "pipe", "select",
                "dup", "nanosleep", "getpid", "socket", "connect",
                "accept", "sendto", "recvfrom", "bind", "listen",
                "getsockname", "exit_group", "futex", "clone",
                "execve", "wait4", "kill", "getppid", "getpgrp"],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

---

## AppArmor (GKE, AKS)

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/api: runtime/default
    # veya özel profil:
    # container.apparmor.security.beta.kubernetes.io/api: localhost/company-api
spec:
  containers:
  - name: api
    ...
```

---

## Privileged Mode (Kaçın)

```yaml
# ❌ ASLA production'da kullanma
securityContext:
  privileged: true    # Container = root erişimi → tüm cluster'a erişim

# ❌ Host namespace'e erişim
spec:
  hostNetwork: true   # Node'un ağ stack'ine erişim
  hostPID: true       # Node'un process'lerine erişim
  hostIPC: true       # Node'un IPC namespace'ine erişim
```

```yaml
# Kyverno ile privileged pod'ları engelle
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: Enforce
  rules:
  - name: no-privileged
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Privileged container kullanılamaz"
      pattern:
        spec:
          containers:
          - =(securityContext):
              =(privileged): "false | null"
```

---

## Security Context Denetimi

```bash
# Cluster'daki root çalışan pod'ları bul
kubectl get pods -A -o json | jq -r '
  .items[] |
  select(
    .spec.securityContext.runAsNonRoot != true and
    (.spec.securityContext.runAsUser == null or .spec.securityContext.runAsUser == 0)
  ) |
  "\(.metadata.namespace)/\(.metadata.name)"'

# privileged container'ları bul
kubectl get pods -A -o json | jq -r '
  .items[] |
  .metadata as $meta |
  .spec.containers[] |
  select(.securityContext.privileged == true) |
  "\($meta.namespace)/\($meta.name)/\(.name)"'

# readOnlyRootFilesystem olmayan container'lar
kubectl get pods -n production -o json | jq -r '
  .items[].spec.containers[] |
  select(.securityContext.readOnlyRootFilesystem != true) |
  .name'
```

---

## Özet — Minimum Güvenli Konfigürasyon

```yaml
# Her production pod için minimum standart
securityContext:                        # Pod seviyesi
  runAsNonRoot: true
  runAsUser: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
- securityContext:                      # Container seviyesi
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: [ALL]
```

> [!IMPORTANT]
> `runAsNonRoot: true` tek başına yeterli değil — `runAsUser` da belirtilmeli. Aksi hâlde Dockerfile'da `USER` tanımı yoksa container root olarak çalışır ve K8s bunu tespit edip pod'u başlatmaz (belirsiz hata).

> [!TIP]
> `readOnlyRootFilesystem: true` ayarlandıktan sonra uygulama `/tmp`, log dizini veya cache gibi yerlere yazamayabilir. Bu dizinler için `emptyDir` volume mount et. Hangi dizinlere yazıldığını `strace -e trace=file` veya `falco` ile tespit edebilirsin.

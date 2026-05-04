# eBPF ile Derin Gözlemlenebilirlik (Deep Tracing)

Prometheus ve ana akım loglama yöntemleri uygulamanın dışa vurduklarını izler. **2026 Black Belt standardı**: Kernel'e doğrudan dokunarak gerçekte ne çalıştığını, sidecar veya agent kullanmadan mikrosaniye bazında görmek.

---

## eBPF Nedir?

Linux kernel'e güvenli biçimde kod enjekte edip OS seviyesinde syscall'ları kanca (hook) atarak izleyen teknoloji. Uygulama kodunda hiçbir değişiklik veya restart gerektirmez.

```
Geleneksel izleme:  Uygulama → log/metric API → agent → backend
eBPF izleme:        Kernel hook → her syscall/network event → user-space export
                    (uygulama habersiz, overhead < %1)
```

**Kullanım alanları:**
- Hangi süreç (PID) hangi dosyayı okudu/yazdı?
- Uygulama ne zaman TCP bağlantısı kurdu, karşı taraf kim?
- OOMKill öncesindeki bellek sızıntıları
- Şifreli (TLS) trafiğin kernel'da açık hali (pre-encryption hook)
- Container escape girişimlerini anlık tespit

---

## Cilium Tetragon — Runtime Security & Tracing

### Kurulum

```bash
helm repo add cilium https://helm.cilium.io
helm install tetragon cilium/tetragon \
  --namespace kube-system \
  --set tetragon.prometheus.enabled=true \
  --set tetragon.prometheus.port=2112

# Tetragon CLI
GOOS=$(go env GOOS); GOARCH=$(go env GOARCH)
curl -L -O "https://github.com/cilium/tetragon/releases/latest/download/tetra-${GOOS}-${GOARCH}.tar.gz"
tar -xzf "tetra-${GOOS}-${GOARCH}.tar.gz"
sudo install tetra /usr/local/bin/
```

### Process Execution İzleme

```bash
# Tüm exec event'lerini canlı izle
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon \
  -c export-stdout -f | tetra getevents --exec

# Sadece production namespace
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon \
  -c export-stdout -f | tetra getevents --exec --namespace production

# Shell çalıştırma tespiti (container escape indicator)
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon \
  -c export-stdout -f | tetra getevents --exec | \
  jq 'select(.process_exec.process.binary | test("bash|sh|python"))'
```

---

## TracingPolicy CRD — Özel eBPF Hook'lar

### TCP Bağlantı İzleme

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: tcp-connect-monitor
spec:
  kprobes:
  - call: "tcp_connect"
    syscall: false
    args:
    - index: 0
      type: "sock"
    selectors:
    - matchArgs:
      - index: 0
        operator: "NotDPort"
        values:
        - "53"    # DNS hariç tüm TCP bağlantıları izle
```

### Hassas Dosya Erişim İzleme

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: sensitive-file-monitor
spec:
  kprobes:
  - call: "security_file_open"
    syscall: false
    args:
    - index: 0
      type: "file"
    selectors:
    - matchArgs:
      - index: 0
        operator: "Prefix"
        values:
        - "/etc/kubernetes"     # K8s config dosyaları
        - "/var/run/secrets"    # Service account token'ları
```

### Privilege Escalation Tespiti ve Engelleme

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: block-privilege-escalation
spec:
  kprobes:
  - call: "commit_creds"    # UID değişikliği (setuid, sudo)
    syscall: false
    selectors:
    - matchActions:
      - action: Sigkill     # Anında proses öldür (runtime enforcement)
```

---

## BCC (BPF Compiler Collection) — Canlı Debugging

```bash
# eBPF araçlı ephemeral debug container
kubectl debug -it <POD_ADI> \
  --image=quay.io/iovisor/bcc:latest \
  --target=<CONTAINER_ADI>
```

**Mevcut araçlar:**

| Araç | Ne Gösterir? |
|:-----|:-------------|
| `tcptop` | Hangi IP/port en çok bandwidth yiyor |
| `filetop` | Anlık I/O yapan dosyalar |
| `execsnoop` | Kısa ömürlü child process'ler |
| `opensnoop` | Açılan dosyalar (PID bazlı) |
| `biolatency` | Disk I/O latency histogram |
| `tcplife` | TCP bağlantı yaşam döngüsü |

```bash
# Hangi IP'lere TCP açıyor?
tcplife -p $(pgrep java)

# Yavaş disk I/O var mı?
biolatency -D 10 1    # 10 sn histogram

# bpftrace — tek satır kernel analizi
bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }'
bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "nginx"/ { printf("%s\n", str(args->filename)); }'
```

---

## eBPF Araç Ekosistemi

| Araç | Güçlü Yanı | Ne Zaman? |
|:-----|:-----------|:----------|
| **Tetragon** | Runtime security + K8s entegrasyonu | Production güvenlik izleme |
| **Pixie** | Sıfır-instrumentation APM (HTTP, gRPC, SQL) | Uygulama performance izleme |
| **BCC** | 70+ hazır araç | Anlık canlı debug |
| **bpftrace** | Tek satır sorgular | Hızlı kernel analizi |
| **Falco** | Kural tabanlı runtime security | Güvenlik event alerting |

```bash
# Pixie — sıfır-instrumentation HTTP izleme
px run px/http_data -- --namespace production
px run px/mysql_data -- --namespace production
```

---

## Prometheus Metrikleri

```promql
# Container'da shell çalıştırma (güvenlik alarm)
rate(tetragon_events_total{type="PROCESS_EXEC",binary=~".*(bash|sh).*"}[5m])

# Privilege escalation girişimleri
rate(tetragon_events_total{type="PROCESS_KPROBE",func_name="commit_creds"}[5m])
```

> [!IMPORTANT]
> eBPF araçları, ağ problemlerini ve CPU leak'lerini çözmek için `strace` gibi yavaş araçların yerini almıştır. Tetragon + Pixie kombinasyonu 2026'da production standart izleme yığınının bir parçasıdır.

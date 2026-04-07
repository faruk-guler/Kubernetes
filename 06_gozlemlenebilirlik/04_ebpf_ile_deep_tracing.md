# eBPF ile Derin Gözlemlenebilirlik (Deep Tracing)

Prometheus ve ana akım loglama yöntemleri uygulamanın dışa vurduklarını izler. Ancak 2026 Black Belt standartlarında hedef **Çekirdeğe (Kernel) doğrudan dokunarak** gerçekte ne çalıştığını, sidecar veya ajan kullanmadan mikrosaniye bazında görmektir.

---

## 4.1 eBPF (Extended Berkeley Packet Filter) Nedir?

Linux çekirdeğine kod (C tabanlı programlar) enjekte edip, OS seviyesinde fonksiyon çağrılarını (Syscall) kanca (hook) atarak izleyen devrimsel ağ ve güvenlik teknolojisidir. Uygulama kodunda hiçbir değişiklik veya Restart gerektirmez!

**Kullanım Alanları:**
- Hangi süreç (PID) hangi dosyayı okudu?
- Uygulama ne zaman DNS isteği yaptı ve ne zaman TCP paketini kernel'a yolladı?
- OOMKilled olmadan saniyeler önceki bellek (memory allocation) sızıntıları.

---

## 4.2 Cilium Tetragon Kurulumu ve Kullanımı

Tetragon, eBPF tabanlı en gelişmiş Runtime Güvenlik ve Gözlemlenebilirlik aracıdır.

```bash
# Tetragon Helm Kurulumu
helm repo add cilium https://helm.cilium.io
helm install tetragon cilium/tetragon -n kube-system

# Tetragon CLI İndirme (Log okumak için)
GOOS=$(go env GOOS)
GOARCH=$(go env GOARCH)
curl -L -O "https://github.com/cilium/tetragon/releases/latest/download/tetra-${GOOS}-${GOARCH}.tar.gz"
tar -xzf tetra-${GOOS}-${GOARCH}.tar.gz
```

### Örnek 1: Çalışan Tüm Process'leri (Exec) İzleme

Bir Pod içinde `/bin/bash` mi çalıştırıldı, yoksa `curl` ile dışarı mı gidiliyor? Loglarda görmeseniz bile Kernel her şeyi bilir:

```bash
# Sadece "exec" edilen komutları göster
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout -f | tetra getevents --exec
```

### Örnek 2: Ağ Seviyesi Tracing (TCP/UDP)

Pod içinde TCP bağlantısı kurulduğu an (şifrelenmiş olsa dahi, TLS öncesi kanca ile) hedefi görmek:
```yaml
# TracingPolicy CRD
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: tcp-connect
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
        - "53"  # DNS dışındaki tüm bağlantılar
```

---

## 4.3 BCC (BPF Compiler Collection) ile Canlı Debugging

Bir Pod'un içinden debug yapmak istediğinizde eBPF tool'ları içeren efemeral container eklersiniz:

```bash
kubectl debug -it <POD_ADI> --image=quay.io/iovisor/bcc:latest --target=<CONTAINER_ADI>
```

İçeri girdikten sonra kullanabileceğiniz eBPF araçları:
- `tcptop`: Hangi IP ve portların o an pod üzerinden en çok bandwidth yediğini gösterir.
- `filetop`: Hangi dosyaların anlık olarak I/O oluşturduğunu gösterir.
- `execsnoop`: Container'ın saniyelik bazda doğurduğu kısa ömürlü child-processleri yakalar.

> [!IMPORTANT]
> Black Belt mühendisler, ağ problemlerini ve CPU leak'leri çözmek için `strace` gibi yavaş araçlar yerine eBPF araçlarını (`bcc`, `tetragon`, `tracee`) kullanırlar!

---
*← [Ana Sayfa](../README.md)*

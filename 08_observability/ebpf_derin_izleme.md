# eBPF ile Derin Gözlemlenebilirlik (eBPF Deep Tracing)

Prometheus ve geleneksel loglama araçları, uygulamaların dış dünyaya sundukları (metrics/logs) ile sınırlıdır. **eBPF (Extended Berkeley Packet Filter)** ise, uygulama koduna dokunmadan, podları yeniden başlatmadan ve sidecar enjekte etmeden doğrudan işletim sistemi çekirdeğine (kernel) sızarak mikrosaniye bazında bir gözlemlenebilirlik sağlar. 2026 yılı kurumsal altyapılarında "Black Belt" seviyesindeki izleme ve güvenlik denetiminin standardı eBPF'tir.

---

## 1. eBPF Nedir ve Nasıl Çalışır?

eBPF, Linux çekirdeğinde güvenli ve korumalı bir sanal makine (sandbox) içinde kullanıcı kodlarının çalıştırılmasını sağlar.

```
[ Uygulama / Pod ]              [ İşletim Sistemi Çekirdeği (Kernel) ]
    KOD DEĞİŞİMİ YOK       ──►   Syscall Hooks (Sistem Çağrısı Yakalama)
    SİDECAR ENJEKTE YOK          eBPF Programı (Overhead < %1)
                                      │
                                      ▼ (Hızlı Veri İhracatı)
                                [ User-Space Ajanı (Tetragon/BCC) ]
```

* **Sıfır Etki (Zero-Instrumentation):** Uygulama üzerinde hiçbir performans kaybına yol açmaz (Overhead <%1).
* **Tam Görünürlük:** Kernel düzeyindeki tüm dosya okuma/yazma, TCP bağlantısı kurma, namespace değişiklikleri ve CPU zamanlamalarını anlık izler.

---

## 2. Cilium Tetragon ile Güvenlik ve İzleme

**Tetragon**, Cilium projesinin altındaki eBPF tabanlı runtime security ve deep tracing aracıdır. eBPF kancalarını kullanarak süreç yürütme (process execution), dosya erişimi ve ağ etkinliklerini anlık gözlemler.

```bash
# 1. Tetragon Kurulumu (Helm)
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon \
  --namespace kube-system \
  --set tetragon.prometheus.enabled=true \
  --set tetragon.prometheus.port=2112

# 2. Tetragon CLI Kurulumu (Linux)
curl -L -O "https://github.com/cilium/tetragon/releases/latest/download/tetra-linux-amd64.tar.gz"
tar -xzf "tetra-linux-amd64.tar.gz"
sudo install tetra /usr/local/bin/
```

### Canlı Süreç (Process Execution) İzleme

```bash
# production namespace'indeki tüm podlarda başlatılan süreçleri anlık izleyin:
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon \
  -c export-stdout -f | tetra getevents --exec --namespace production

# Saldırganların shell (bash/sh) çalıştırma girişimlerini jq ile yakalama:
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon \
  -c export-stdout -f | \
  jq 'select(.process_exec.process.binary | test("bash|sh|python|perl"))'
```

---

## 3. TracingPolicy CRD: Özel Kernel Kancaları

Tetragon, kernel içindeki belirli fonksiyonları dinlemek için **TracingPolicy** CRD nesnelerini kullanır.

### A. TCP Bağlantı İzleme (Ağ Hareketleri)

Podların kurduğu tüm TCP bağlantılarını IP ve Port bazında kernel seviyesinde izlemek için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ebpf_derin_izleme_manifest_1.yaml](../Manifests/08_observability/ebpf_derin_izleme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Hassas Dosya Erişim İzleme (Dosya Güvenliği)

Konteyner içinden `/etc/shadow` veya `/etc/passwd` gibi kritik sistem dosyalarının okunma girişimlerini yakalamak için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ebpf_derin_izleme_manifest_2.yaml](../Manifests/08_observability/ebpf_derin_izleme_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. Yetki Yükseltme (Privilege Escalation) Tespiti

Konteyner içindeki bir sürecin yetkilerini root düzeyine çıkarma girişimini (`commit_creds` kernel fonksiyonunu çağırarak) algılamak için:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [ebpf_derin_izleme_manifest_3.yaml](../Manifests/08_observability/ebpf_derin_izleme_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. BCC (BPF Compiler Collection) ve bpftrace ile Canlı Hata Ayıklama

Kümedeki bir podun CPU leak veya yavaş I/O yaptığı durumlarda, node üzerinde **BCC** araçları çalıştırılarak canlı kernel analizi gerçekleştirilebilir:

```bash
# Hedef podun konteynerine BCC yüklü geçici bir debug podu bağlayın:
kubectl debug -it app-pod --image=quay.io/iovisor/bcc:latest --target=app-container
```

### BCC Canlı Sorun Giderme Araç Seti

* `tcptop`: Hangi IP ve portun anlık en fazla network bant genişliğini (bandwidth) harcadığını gösterir.
* `filetop`: Node üzerinde en çok okuma/yazma (I/O) yapan dosyaları ve bunları tetikleyen PID'leri listeler.
* `execsnoop`: Sistemde milisaniyeler içinde başlayıp biten kısa ömürlü (zombi olmaya aday) süreçleri listeler.
* `opensnoop`: Hangi sürecin hangi sistem dosyasını açtığını anlık gösterir.

### bpftrace ile Tek Satır Kernel Analizleri

```bash
# 1. Hangi process'in kaç adet sistem çağrısı (syscall) gönderdiğini sayın:
bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }'

# 2. Sadece nginx süreci tarafından açılan dosyaları ekrana yazdırın:
bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "nginx"/ { printf("Dosya: %s\n", str(args->filename)); }'
```

---

## 5. eBPF Araç Ekosistemi Karşılaştırma Matrisi

| Araç | Güçlü Olduğu Alan | En Uygun Kullanım Senaryosu |
|:---|:---|:---|
| **Tetragon** | Kubernetes etiket entegrasyonu, yetki kısıtlama, engelleme (Sigkill). | Üretim (production) ortamında anlık tehdit engelleme. |
| **Pixie** | Sıfır kod değişikliğiyle APM (Uygulama Performans İzleme: HTTP, SQL, gRPC). | Kodlara dokunmadan veri tabanı sorgu sürelerini çıkarma. |
| **BCC** | 70+ hazır ve olgunlaşmış terminal aracı. | Canlı ortamda sunucu düzeyinde anlık performans analizi. |
| **bpftrace** | Esnek, tek satırlık (on-liner) sorgu yeteneği. | Ad-hoc kernel analizi ve prototipleme. |

---

## 6. eBPF Verilerinden Prometheus Uyarıları Üretme

Tetragon'un ürettiği eBPF olay metriklerini kullanarak PrometheusRule üzerinde güvenlik alarmları kurgulayabilirsiniz:

```promql
# 1. Konteyner içinde yetkisiz shell (bash/sh) çalıştırıldığında tetiklenen alarm:
rate(tetragon_events_total{type="PROCESS_EXEC", binary=~".*(bash|sh).*"}[5m]) > 0

# 2. Yetki yükseltme (kernel privilege escalation) denemeleri:
rate(tetragon_events_total{type="PROCESS_KPROBE", func_name="commit_creds"}[5m]) > 0
```

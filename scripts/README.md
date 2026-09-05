# 🛠️ Kubernetes Zero to Hero — Operasyonel ve Teşhis Betikleri (Scripts Catalog)

Bu dizin (`scripts/`), Kubernetes kümelerinde karşılaşılan operasyonel zorlukları, hata ayıklama süreçlerini, yedekleme ve güvenlik denetimlerini tek komutla çözmek için geliştirilmiş **20 adet production-grade Bash otomasyon betiğini** barındırır.

Tüm betikler Linux ve Git Bash (Windows) uyumlu olup, Unix (`LF`) satır sonları ile formatlanmıştır.

---

## 📋 Betik Kataloğu ve Kullanım Rehberi

| Betik Adı | Amacı ve İşlevi | Kullanım Örneği | İlgili Bölüm |
| :--- | :--- | :--- | :--- |
| [`setup_local_lab.sh`](setup_local_lab.sh) | 1 Master + 2 Worker düğümlü Kind test kümesini Ingress port yönlendirmeleriyle ayağa kaldırır. | `bash scripts/setup_local_lab.sh` | [02_getting_started/01](../02_getting_started/01_yerel_gelistirme_ortamlari.md) |
| [`create_developer_kubeconfig.sh`](create_developer_kubeconfig.sh) | Geliştiriciler için X.509 istemci sertifikası üretip namespace kısıtlı bağımsız kubeconfig dosyası oluşturur. | `bash scripts/create_developer_kubeconfig.sh <user> <ns>` | [02_getting_started/05](../02_getting_started/05_kubeconfig.md) |
| [`decode_secret.sh`](decode_secret.sh) | Kubernetes Secret içerisindeki tüm base64 verilerini tek hamlede deşifre edip düz metin olarak listeler. | `bash scripts/decode_secret.sh <secret_name> [ns]` | [03_core/11](../03_core/11_configmap_ve_secret.md) |
| [`audit_deprecated_apis.sh`](audit_deprecated_apis.sh) | Küme yükseltmesi öncesi yürürlükten kalkan (deprecated) API'leri tarar. | `bash scripts/audit_deprecated_apis.sh` | [04_infrastructure/17](../04_infrastructure/17_kume_guncelleme.md) |
| [`audit_security_risks.sh`](audit_security_risks.sh) | Root ile koşan, privileged yetkili ve hostNetwork kullanan tehlikeli pod'ları puanlayarak raporlar. | `bash scripts/audit_security_risks.sh` | [08_security/02](../08_security/02_kume_sikilastirma.md) |
| [`audit_cert_expirations.sh`](audit_cert_expirations.sh) | API Server, etcd ve Kubelet TLS sertifikalarının kalan gün sürelerini tarar ve uyarır. | `bash scripts/audit_cert_expirations.sh` | [08_security/02](../08_security/02_kume_sikilastirma.md) |
| [`generate_network_policy.sh`](generate_network_policy.sh) | Terminalde interaktif sorular sorarak hatasız NetworkPolicy YAML tanımı üretir. | `bash scripts/generate_network_policy.sh` | [08_security/11](../08_security/11_networkpolicy_derin_dalis.md) |
| [`capture_java_go_pprof.sh`](capture_java_go_pprof.sh) | Canlı Go ve Java pod'larından pprof / JFR CPU ve bellek profili çekerek diske indirir. | `bash scripts/capture_java_go_pprof.sh <pod> [ns] [go\|java]` | [09_observability/10](../09_observability/10_surekli_profil_cikarma_pyroscope.md) |
| [`report_resource_waste.sh`](report_resource_waste.sh) | Requests/limits tanımlanmamış pod'ları ve rezerve edilip atıl duran CPU/RAM israfını FinOps için raporlar. | `bash scripts/report_resource_waste.sh` | [11_platform/05](../11_platform/05_finops_ve_maliyet_optimizasyonu.md) |
| [`diagnose_pod_crashes.sh`](diagnose_pod_crashes.sh) | CrashLoopBackOff, OOMKilled ve ImagePullBackOff durumlarını önceki loglar ve exit code ile analiz eder. | `bash scripts/diagnose_pod_crashes.sh <pod> [ns]` | [14_troubleshooting/03](../14_troubleshooting/03_pod_ve_konteyner_sorun_giderme.md) |
| [`cleanup_stuck_resources.sh`](cleanup_stuck_resources.sh) | Terminating aşamasında takılan Namespace, Pod ve PVC'lerin finalizer blokajlarını güvenle kaldırır. | `bash scripts/cleanup_stuck_resources.sh <type> <name> [ns]` | [14_troubleshooting/03](../14_troubleshooting/03_pod_ve_konteyner_sorun_giderme.md) |
| [`quick_node_maintenance.sh`](quick_node_maintenance.sh) | Düğümleri güvenle bakıma alma (drain), kordonlama (cordon) ve tekrar aktif etme (uncordon) işlemlerini yönetir. | `bash scripts/quick_node_maintenance.sh drain <node>` | [14_troubleshooting/04](../14_troubleshooting/04_dugum_node_sorun_giderme.md) |
| [`cluster_health_check.sh`](cluster_health_check.sh) | Küme sağlığını (Node, Control Plane, etcd, CoreDNS, pod yeniden başlama oranları) tarar. | `bash scripts/cluster_health_check.sh` | [14_troubleshooting/04](../14_troubleshooting/04_dugum_node_sorun_giderme.md) |
| [`test_pod_connectivity.sh`](test_pod_connectivity.sh) | Geçici bir curl pod'u ile küme içi veya dışı hedeflere ağ erişilebilirliğini ve gecikmeyi ölçer. | `bash scripts/test_pod_connectivity.sh <url_or_ip> [port]` | [14_troubleshooting/06](../14_troubleshooting/06_ag_sorun_giderme.md) |
| [`capture_pod_packet_trace.sh`](capture_pod_packet_trace.sh) | Canlı pod ağına ephemeral debug konteyneri ile bağlanarak `.pcap` formatında paket yakalar. | `bash scripts/capture_pod_packet_trace.sh <pod> [ns] [sec]` | [14_troubleshooting/06](../14_troubleshooting/06_ag_sorun_giderme.md) |
| [`debug_dns.sh`](debug_dns.sh) | CoreDNS pod loglarını, upstream DNS sunucularını ve domain çözümleme hızlarını denetler. | `bash scripts/debug_dns.sh` | [14_troubleshooting/06](../14_troubleshooting/06_ag_sorun_giderme.md) |
| [`audit_unused_pvc_storage.sh`](audit_unused_pvc_storage.sh) | Hiçbir pod'a bağlı olmayan ve gereksiz maliyet oluşturan sahipsiz PVC'leri tespit eder. | `bash scripts/audit_unused_pvc_storage.sh` | [14_troubleshooting/07](../14_troubleshooting/07_depolama_sorun_giderme.md) |
| [`backup_pvc_to_local.sh`](backup_pvc_to_local.sh) | Canlı bir PVC içindeki tüm verileri tar ile sıkıştırarak yerel bilgisayara indirir. | `bash scripts/backup_pvc_to_local.sh <pvc> [ns] [output.tar.gz]` | [14_troubleshooting/07](../14_troubleshooting/07_depolama_sorun_giderme.md) |
| [`backup_etcd_snapshot.sh`](backup_etcd_snapshot.sh) | Control Plane üzerinde etcd snapshot yedeği alıp anında dosya bütünlüğünü test eder. | `bash scripts/backup_etcd_snapshot.sh [backup_dir]` | [14_troubleshooting/08](../14_troubleshooting/08_etcd_yedekleme_ve_geri_yukleme.md) |
| [`export_clean_cluster_yamls.sh`](export_clean_cluster_yamls.sh) | Kümedeki kaynakları status/uid alanlarından arındırılmış temiz YAML olarak arşivler. | `bash scripts/export_clean_cluster_yamls.sh [dir] [ns]` | [14_troubleshooting/10](../14_troubleshooting/10_velero_ile_yedekleme.md) |

---

## ⚙️ Gereksinimler ve Ön Koşullar

Bu betiklerin çalıştırılabilmesi için sisteminizde aşağıdaki CLI araçlarının bulunması tavsiye edilir:

- `bash` (Linux / macOS veya Windows için Git Bash)
- `kubectl` (v1.28+)
- `jq` (JSON verilerini filtrelemek için)
- `curl` ve `tar`
- `openssl` (Sertifika ve kubeconfig işlemleri için)
- `etcdctl` (etcd yedekleme betiği için, Master düğüm üzerinde)

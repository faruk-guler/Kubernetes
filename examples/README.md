# 📂 Kubernetes YAML Örnekleri (Examples)

Bu dizin, Kubernetes mimarisinde kullanılan tüm temel objelerin, yapılandırmaların ve uygulama senaryolarının 2026 standartlarına uygun örneklerini içerir.

## 🚀 Kategori Dizini

| Dizin | Açıklama |
|:---|:---|
| 00_docker/ | Modern Docker imaj (Node.js, Python) örnekleri |
| 01_core/ | Pod, Deployment, StatefulSet, DaemonSet |
| 02_workloads/ | Job ve CronJob (Tekil/Zamanlanmış görevler) |
| 03_networking/ | Service, Ingress, Gateway API, NetworkPolicy |
| 04_configs_secrets/ | ConfigMap ve Secret yönetimi |
| 05_storage/ | PV, PVC, StorageClass (Depolama) |
| 06_security_rbac/ | RBAC ve PodDisruptionBudget (Güvenlik) |
| 07_resource_management/ | HPA, VPA, Quota, PriorityClass |
| 08_cluster_admin/ | Namespace ve Küme Yönetimi |
| 09_apps/ | Klasik Uygulama Örnekleri (Wordpress, Zabbix vb.) |

---
## 🛡️ 2026 Standartları Notu
Tüm örnekler şu prensiplere göre hazırlanmıştır:
1. **SecurityContext**: Rootless çalışan ve kısıtlayıcı kernel yetkilerine sahip container'lar.
2. **Resources**: Kesin tanımlanmış `requests` ve `limits` değerleri.
3. **Probes**: Liveness ve Readiness sağlık kontrolleri.
4. **Gateway API**: Ingress yerine modern ağ yönlendirmesi.

---
*← Ana Sayfa*

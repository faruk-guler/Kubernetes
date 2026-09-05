# 📦 Kubernetes Zero to Hero — Üretim Düzeyi Manifestolar Kataloğu (Manifests Catalog)

Bu dizin (`manifests/`), kitaptaki 15 modülün tamamını destekleyen, gerçek dünya ve kurumsal üretim (production) standartlarına uygun **42 adet doğrulanmış Kubernetes manifestosu** barındırır.

Tüm manifestolar `kubectl apply --dry-run=client` ve YAML sözdizim testlerinden geçmiş olup, Kubernetes v1.30+ / v1.32 standartlarıyla uyumludur.

---

## 📋 Manifesto Kataloğu ve İlgili Bölümler

| Manifesto Dosyası | Kaynak Türü / Amacı | İlgili Bölüm |
| :--- | :--- | :--- |
| [`01_container_buildx_multiarch_pipeline.yaml`](01_container_buildx_multiarch_pipeline.yaml) | GitHub Actions çoklu mimari (ARM64/AMD64) derleme hattı | [01_containers/03](../01_containers/03_coklu_mimari_imaj_derleme.md) |
| [`01_containerd_production_config.yaml`](01_containerd_production_config.yaml) | Sertleştirilmiş containerd cgroupv2 & registry mirror konfigürasyonu | [01_containers/04](../01_containers/04_konteyner_calisma_zamani_ve_kayit_defteri.md) |
| [`02_k3d_local_dev_cluster.yaml`](02_k3d_local_dev_cluster.yaml) | Çok düğümlü yerel k3d test kümesi yapılandırması | [02_getting_started/02](../02_getting_started/02_k3d.md) |
| [`02_multi_cluster_kubeconfig.yaml`](02_multi_cluster_kubeconfig.yaml) | Çoklu küme (Dev/Staging/Prod) kubeconfig şablonu | [02_getting_started/05](../02_getting_started/05_kubeconfig.md) |
| [`03_production_microservice_workload.yaml`](03_production_microservice_workload.yaml) | Liveness/readiness problu, HPA ve PDB uyumlu mikroservis Deployment | [03_core/14](../03_core/14_deployment_derinlemesine_inceleme.md) |
| [`03_scheduled_database_backup_cronjob.yaml`](03_scheduled_database_backup_cronjob.yaml) | Güvenli veritabanı yedeği alan CronJob tanımı | [03_core/16](../03_core/16_jobs_ve_cronjobs.md) |
| [`03_statefulset_and_daemonset_workloads.yaml`](03_statefulset_and_daemonset_workloads.yaml) | Günlük toplayıcı DaemonSet ve durumlu StatefulSet şablonu | [03_core/15](../03_core/15_daemonset.md) |
| [`04_high_availability_pdb_and_quotas.yaml`](04_high_availability_pdb_and_quotas.yaml) | PodDisruptionBudget ve ResourceQuota yüksek erişilebilirlik politikası | [04_infrastructure/06](../04_infrastructure/06_pod_disruption_budget.md) |
| [`04_karpenter_autoscaling_stack.yaml`](04_karpenter_autoscaling_stack.yaml) | AWS EKS üzerinde Karpenter NodePool ve EC2NodeClass tanımı | [04_infrastructure/09](../04_infrastructure/09_karpenter.md) |
| [`04_keda_event_driven_autoscaler.yaml`](04_keda_event_driven_autoscaler.yaml) | RabbitMQ/Kafka kuyruk uzunluğuna göre KEDA ScaledObject | [04_infrastructure/08](../04_infrastructure/08_keda_ile_otomatik_olceklendirme.md) |
| [`05_kubeadm_ha_cluster_init.yaml`](05_kubeadm_ha_cluster_init.yaml) | Kubeadm ile harici yük dengeleyicili HA kontrol düzlemi kurulumu | [05_installations/02](../05_installations/02_kubeadm_ile_kurulum.md) |
| [`05_rke2_hardened_cluster_config.yaml`](05_rke2_hardened_cluster_config.yaml) | CIS Benchmark uyumlu RKE2 küme yapılandırması | [05_installations/03](../05_installations/03_rke2_kurulumu.md) |
| [`05_talos_linux_controlplane.yaml`](05_talos_linux_controlplane.yaml) | Değişmez (Immutable) Talos Linux kontrol düzlemi şablonu | [05_installations/04](../05_installations/04_talos_linux.md) |
| [`06_gateway_api_and_canary_traffic_split.yaml`](06_gateway_api_and_canary_traffic_split.yaml) | Gateway API HTTPRoute ile kanarya ağırlıklı trafik yönlendirme | [06_networking/05](../06_networking/05_gateway_api.md) |
| [`06_production_ingress_nginx_tls.yaml`](06_production_ingress_nginx_tls.yaml) | Let's Encrypt TLS sertifikalı NGINX Ingress tanımı | [06_networking/02](../06_networking/02_service_ve_ingress.md) |
| [`06_zero_trust_cilium_network_policy.yaml`](06_zero_trust_cilium_network_policy.yaml) | Sıfır güven mimarisi için Cilium L7 HTTP ve DNS filtreleme | [06_networking/08](../06_networking/08_cilium_ebpf.md) |
| [`07_cloudnative_postgresql_ha_cluster.yaml`](07_cloudnative_postgresql_ha_cluster.yaml) | Otomatik failover özellikli CloudNativePG PostgreSQL kümesi | [07_storage/06](../07_storage/06_cloudnativepg.md) |
| [`07_dynamic_ebs_storageclass_and_statefulset.yaml`](07_dynamic_ebs_storageclass_and_statefulset.yaml) | AWS gp3 EBS dinamik depolama sınıfı ve PVC şablonu | [07_storage/02](../07_storage/02_pv_pvc_ve_storageclass.md) |
| [`07_rook_ceph_cluster.yaml`](07_rook_ceph_cluster.yaml) | Bare-metal ortamlar için Rook Ceph blok/dosya depolama kümesi | [07_storage/07](../07_storage/07_rook_ceph_ve_longhorn.md) |
| [`07_strimzi_kafka_kraft_cluster.yaml`](07_strimzi_kafka_kraft_cluster.yaml) | ZooKeeper'sız KRaft modunda kurumsal Apache Kafka kümesi | [07_storage/08](../07_storage/08_kafka_ve_strimzi_operator.md) |
| [`07_volume_snapshot_and_restore.yaml`](07_volume_snapshot_and_restore.yaml) | CSI VolumeSnapshot ve anlık görüntüden geri yükleme (restore) | [07_storage/04](../07_storage/04_volume_anlik_goruntuleri_ve_klonlama.md) |
| [`08_enterprise_rbac_and_workload_identity.yaml`](08_enterprise_rbac_and_workload_identity.yaml) | En az yetki prensipli Role, RoleBinding ve ServiceAccount | [08_security/04](../08_security/04_rol_tabanli_erisim_kontrolu_rbac.md) |
| [`08_hardened_security_context_and_vault_secret.yaml`](08_hardened_security_context_and_vault_secret.yaml) | ReadOnlyRootFilesystem, non-root ve HashiCorp Vault SecretPod | [08_security/06](../08_security/06_security_context.md) |
| [`08_validating_admission_policy_and_kyverno.yaml`](08_validating_admission_policy_and_kyverno.yaml) | K8s yerel ValidatingAdmissionPolicy ve Kyverno güvenlik kuralları | [08_security/09](../08_security/09_admission_policy_derin_dalis.md) |
| [`09_loki_tempo_pyroscope_observability.yaml`](09_loki_tempo_pyroscope_observability.yaml) | Grafana LGTM yığını (Loki günlük, Tempo izleme, Pyroscope profil) | [09_observability/04](../09_observability/04_loki_log_yonetimi.md) |
| [`09_opentelemetry_collector_pipeline.yaml`](09_opentelemetry_collector_pipeline.yaml) | OpenTelemetry Collector DaemonSet ve pipeline konfigürasyonu | [09_observability/06](../09_observability/06_opentelemetry.md) |
| [`09_prometheus_rules_and_slack_alerts.yaml`](09_prometheus_rules_and_slack_alerts.yaml) | PrometheusRule alarmları ve Slack bildirim kanalı entegrasyonu | [09_observability/01](../09_observability/01_prometheus_derinlemesine_inceleme.md) |
| [`10_argo_rollouts_canary_with_analysis.yaml`](10_argo_rollouts_canary_with_analysis.yaml) | Otomatik Prometheus metriği denetimli Argo Rollouts Canary | [10_gitops/11](../10_gitops/11_argo_rollouts.md) |
| [`10_argocd_root_app_and_applicationsets.yaml`](10_argocd_root_app_and_applicationsets.yaml) | App-of-Apps kalıbı ve çok kümeli ApplicationSet | [10_gitops/08](../10_gitops/08_argocd_applicationset.md) |
| [`10_external_secrets_vault_integration.yaml`](10_external_secrets_vault_integration.yaml) | External Secrets Operator (ESO) ve SecretStore yapılandırması | [10_gitops/13](../10_gitops/13_external_secrets.md) |
| [`10_flagger_canary_release.yaml`](10_flagger_canary_release.yaml) | Flagger ve NGINX/Istio tabanlı aşamalı sürüm dağıtımı | [10_gitops/17](../10_gitops/17_flagger_ile_canary_dagitim.md) |
| [`10_flux_v2_gitops_reconciler.yaml`](10_flux_v2_gitops_reconciler.yaml) | Flux v2 GitRepository ve Kustomization reconciliation tanımı | [10_gitops/09](../10_gitops/09_flux_v2.md) |
| [`10_github_actions_runner.yaml`](10_github_actions_runner.yaml) | Actions Runner Controller (ARC) ile kendi kendini ölçekleyen runner | [10_gitops/16](../10_gitops/16_github_actions_ve_arc.md) |
| [`11_backstage_software_catalog_component.yaml`](11_backstage_software_catalog_component.yaml) | İç Geliştirici Platformu (IDP) Backstage servis kataloğu tanımı | [11_platform/02](../11_platform/02_backstage_idp.md) |
| [`11_crossplane_self_service_cloud_database.yaml`](11_crossplane_self_service_cloud_database.yaml) | Crossplane XRD ve Composition ile self-service AWS RDS veritabanı | [11_platform/03](../11_platform/03_crossplane.md) |
| [`12_cluster_api_capi_workload_cluster.yaml`](12_cluster_api_capi_workload_cluster.yaml) | Cluster API (CAPI) ile bildirimsel iş yükü kümesi tanımı | [12_multicluster/04](../12_multicluster/04_cluster_api_capi.md) |
| [`12_karmada_and_vcluster_multi_tenancy.yaml`](12_karmada_and_vcluster_multi_tenancy.yaml) | Sanal küme (vCluster) ve Karmada çoklu küme dağıtım politikası | [12_multicluster/03](../12_multicluster/03_vcluster.md) |
| [`13_kserve_vllm_llm_inference_service.yaml`](13_kserve_vllm_llm_inference_service.yaml) | KServe ve vLLM çalışma zamanı ile yüksek performanslı LLM sunumu | [13_ai/05](../13_ai/05_kserve_ve_model_sunumu.md) |
| [`13_ray_cluster_and_gpu_workload.yaml`](13_ray_cluster_and_gpu_workload.yaml) | KubeRay operatörü ile dağıtık GPU yapay zeka eğitim kümesi | [13_ai/04](../13_ai/04_ray_ile_dagitik_hesaplama.md) |
| [`14_automated_etcd_backup_cronjob.yaml`](14_automated_etcd_backup_cronjob.yaml) | TLS korumalı etcd anlık görüntü yedeği alan otomatik CronJob | [14_troubleshooting/08](../14_troubleshooting/08_etcd_yedekleme_ve_geri_yukleme.md) |
| [`14_chaos_mesh_resilience_experiment.yaml`](14_chaos_mesh_resilience_experiment.yaml) | Chaos Mesh ile PodKill ve NetworkLatency kaos deneyi | [14_troubleshooting/12](../14_troubleshooting/12_kaos_muhendisligi_litmus_ve_chaos_mesh.md) |
| [`15_cka_cks_exam_mastery_blueprint.yaml`](15_cka_cks_exam_mastery_blueprint.yaml) | CKA & CKS sınav hazırlık laboratuvarı ve kontrol matrisi | [15_migration/04](../15_migration/04_cka_ckad_cks_sertifikasyon_rehberi.md) |

---

## 🚀 Hızlı Kullanım

Tüm manifestolar bağımsız olarak uygulanabilir:

```bash
# Örnek: Üretim düzeyi mikroservis iş yükünü dağıtın
kubectl apply -f manifests/03_production_microservice_workload.yaml

# Örnek: Sıfır güven ağ politikasını kuru çalıştırma (dry-run) ile test edin
kubectl apply -f manifests/06_zero_trust_cilium_network_policy.yaml --dry-run=client
```

# İyi Pratikler (Best Practices)

## Erişilebilirlik (Availability)

* Liveness ve Readiness probe'ları doğru şekilde yapılandırıldı mı?
* Master Node'lar tek sayı ve en az 3 tane mi?
* ETCD servisleri izole edildi mi?
* Düzenli etcd yedeklemeleri için bir planınız var mı?
* Master Node'lar bölgeler (AZ/Region) arası dağıtıldı mı?
* Worker (İşçi) Node'lar bölgeler (AZ/Region) arası dağıtıldı mı? 
* Master ve Worker Node'lar için Autoscaling (Otomatik Ölçeklendirme) ayarlandı mı?
* HA (Yüksek Erişilebilirlik) yük dengeleme oluşturuldu mu?
* Scheduler ve Controller Manager için aktif-pasif yapılandırma var mı?
* Yüksek erişilebilirlik için doğru sayıda pod kopyası oluşturuldu mu?
* Çıplak (Naked/Unmanaged) pod'lar ayağa kaldırılıyor mu? (Deployment olmadan pod kullanımı)
* Çoğul küme (Multi-Cluster) federasyonu yapılandırıldı mı?
* etcd servisleri için heartbeat ve master seçim zaman aşımı (election timeout) ayarlandı mı?
* Ingress yapılandırıldı mı?

## Kaynak Yönetimi (Resource Management)

* Konteynerler için kaynak istekleri (Requests) ve sınırları (Limits) yapılandırıldı mı?
* Yerel geçici depolama için (ephemeral-storage) kaynak istekleri ve sınırları yapılandırıldı mı?
* Ekipleriniz için ayrı ad alanları (Namespaces) oluşturdunuz mu?
* Ad alanları için varsayılan kaynak istekleri, sınır aralıkları (LimitRanges) yapılandırıldı mı?
* Ad alanları için Pod ve API Kotaları (ResourceQuotas) yapılandırıldı mı?
* Etcd için yeterli kaynak sağlandı mı?
* Etcd için anlık bellek (memory) kullanımı yapılandırıldı mı?
* Kubernetes nesnelerine etiketler (Labels) eklendi mi?
* Bir düğümde çalışabilen pod sayısı (max-pods) sınırlandı mı?
* Sistem arka plan programları (kubelet, kube-proxy vb.) için ayrılmış işlem kaynakları (System Reserved) yapılandırıldı mı?
* API sunucusu için API istek işleme oranları yapılandırıldı mı?
* Kaynak kalmaması (OOM/Starvation) durumunda yapılacaklar (Eviction Policy) yapılandırıldı mı?
* PersistentVolumes için önerilen ayarları mı kullanıyorsunuz?
* Etkinleştirilmiş log döndürme (Log rotation) var mı?
* Kubelet'in etiket anahtarlarını ayarlamasını veya değiştirmesini engellediniz mi? (NodeRestriction)

## Güvenlik (Security)

* En son Kubernetes sürümünü mü kullanıyorsunuz?
* Etkin RBAC (Rol Tabanlı Erişim Kontrolü) var mı?
* Kullanıcı erişimiyle ilgili en iyi uygulamaları takip ediyor musunuz? (En az yetki prensibi - Least Privilege)
* Denetim günlüğü (Audit Log) etkinleştirildi mi?
* Bastion host (Kale barındırıcısı) mu kuruyorsunuz? (Erişim için proxy/ara sistem)
* Kabul denetleyicisinde (Admission Controller) AlwaysPullImages etkinleştirildi mi?
* Pod Güvenlik Politikası (Kyverno/PSS) tanımlandı ve etkinleştirildi mi?
* Bir Ağ eklentisi (CNI) ve yapılandırılmış ağ politikaları (NetworkPolicies) seçtiniz mi?
* Kubelet için kimlik doğrulama (Authentication) uygulandı mı?
* Kubernetes Sırlarını (Secrets/SealedSecrets) yapılandırdınız mı?
* Beklemede veri (Data/etcd at Rest) şifrelemeyi etkinleştirdiniz mi?
* Uygulamalar üzerinde Varsayılan Hizmet Hesabı (default ServiceAccount) devre dışı bırakılsın mı?
* Güvenlik açıkları için konteyner imajları (Trivy/Clair) tarandı mı?
* Podlar, konteynerler ve birimler için yapılandırılmış güvenlik bağlamı (SecurityContext/runAsNonRoot) var mı?
* Açık Kubernetes loglama etkinleştirildi mi?

## Ölçeklendirme (Scaling)

* Yatay ölçeklendirme (HPA - Horizontal Pod Autoscaler) yapılandırıldı mı?
* Dikey ölçeklendirme (VPA - Vertical Pod Autoscaler) yapılandırıldı mı?
* Küme ölçeklendirme (Cluster Autoscaler / Karpenter) yapılandırıldı mı?

## Depolama Yönetimi (Storage Management)

* Kalıcı Birimler (PV) için Bulut sağlayıcısı tarafından önerilen ayarları kullanın (CSI sürücüleri).
* PVC'yi dağıtım konfigürasyonuna dahil edin ve asla doğrudan PV talep kullanmayın.
* Varsayılan bir depolama sınıfı (StorageClass) oluşturun.
* Kullanıcıya esnek depolama sınıfları sağlayın.

## İzleme, Uyarı ve Analiz (Observability)

* İzleme hattı (Prometheus vs.) kuruldu mu?
* İzlemek için kritik metrik/ölçüm listeleri (Grafana Dashboard) oluşturuldu mu?

## CI/CD ve GitOps

* Sürekli Teslimat için Güvenli CI/CD hatları (Pipelines) uygulayın.
* İzlenebilirliği artırmak için onay iş akışıyla GitOps'u (ArgoCD/Flux) etkinleştirin.
* Güvenlik açıklarını test edin, entegre edin ve tarayın (Shift-left security).
* Konteyner imajları oluşturun ve kurumsal güvenli bir depoda (Nexus/Harbor) tutun.
* Denetlenebilirliği artırmak için imajları Git commit SHA ile (tag olarak) etiketleyin. "Latest" tag kullanmaktan kaçının.
* Kesinti süresini önlemek için Rolling Update ve/veya Blue-Green/Canary deployment modellerini benimseyin.

## Ekstra Tavsiyeler

* Uçtan uca test (e2e test) planınız yapıldı mı?
* Dış servisleri (ExternalName / Service) Kubernetes içinden lokalmiş gibi erişilecek şekilde tasarladınız mı?

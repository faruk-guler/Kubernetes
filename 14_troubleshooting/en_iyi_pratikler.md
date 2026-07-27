# Kubernetes Üretim Ortamı (Production) En İyi Pratikleri

Kubernetes üzerinde uygulamaları canlıya (production) alırken sistemin yüksek erişilebilir, güvenli, ölçeklenebilir ve izlenebilir olması kritik önem taşır. Bu doküman, üretim ortamı dağıtımlarında kontrol edilmesi ve uygulanması gereken en iyi pratikleri (best practices) ve rehber kod örneklerini sunar.

---

## 1. Yüksek Erişilebilirlik (Availability & Resilience)

* **Çoklu Kontrol Düzlemi (HA Control Plane):** Kontrol düzlemi (Control Plane) düğümleri tek sayı (en az 3 master node) ve farklı fiziksel sunuculara veya bulut bölgelerine (Availability Zones) dağıtılmış olmalıdır.
* **Worker Node Dağılımı:** Worker node'lar da yüksek erişilebilirlik için bölgeler arası dağıtılmalıdır. Pod'ların farklı bölgelerdeki düğümlere dağılmasını zorunlu kılmak için `topologySpreadConstraints` kullanılmalıdır:

    ```yaml
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: billing-api
    ```

* **Liveness, Readiness ve Startup Probe'ları:** Her pod için uygun sağlık kontrolleri tanımlanmalıdır.
  * *Readiness Probe:* Pod'un trafiği kabul etmeye hazır olup olmadığını belirler.
  * *Liveness Probe:* Pod'un kilitlenip kilitlenmediğini ve yeniden başlatılması gerekip gerekmediğini denetler.
  * *Startup Probe:* Yavaş başlayan uygulamalar için ilk açılış aşamasını yönetir.
* **PodDisruptionBudget (PDB):** Küme güncellemeleri veya düğüm bakımları sırasında servis kesintisini önlemek için PDB kullanılmalıdır:

    📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [en_iyi_pratikler_manifest_1.yaml](../Manifests/13_troubleshooting/en_iyi_pratikler_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

* **Çıplak Pod'lardan Kaçınma:** Asla doğrudan `kind: Pod` ile yönetilmeyen pod ayağa kaldırılmamalıdır. Her zaman `Deployment`, `StatefulSet` veya `DaemonSet` kullanılmalıdır.

---

## 2. Kaynak Yönetimi ve Optimizasyon (Resource Management)

* **Requests ve Limits Tanımları:** Tüm konteynerlerde CPU ve Bellek için `requests` ve `limits` tanımları yapılmalıdır. Bu, podların QoS (Quality of Service) sınıflarını (Guaranteed veya Burstable) belirler ve OOMKilled durumlarını önler:

    ```yaml
    resources:
      requests:
        memory: "256Mi"
        cpu: "250m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    ```

* **LimitRanges ve ResourceQuotas:** Ad alanlarında (namespaces) kontrolsüz kaynak tüketimini engellemek için kotalar tanımlanmalıdır:

    📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [en_iyi_pratikler_manifest_2.yaml](../Manifests/13_troubleshooting/en_iyi_pratikler_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

* **Sistem Kaynaklarının Rezerve Edilmesi (System Reserved):** Kubelet yapılandırmasında, işletim sisteminin ve Kubernetes bileşenlerinin (kubelet, container runtime vb.) çökmesini önlemek için sistem kaynak rezervasyonu yapılmalıdır:

    ```yaml
    systemReserved:
      cpu: 500m
      memory: 1Gi
    ```

---

## 3. Güvenlik ve Uyum (Security & Compliance)

* **En Az Yetki Prensibi (Least Privilege):** RBAC kurallarında wildcards (`*`) yerine spesifik API grupları, kaynaklar ve fiiller (verbs) kullanılmalıdır.
* **runAsNonRoot ve Salt Okunur Dosya Sistemi:** Pod'ların root kullanıcısı ile çalışması engellenmeli, dosya sistemi yazma izinleri kısıtlanmalıdır:

    ```yaml
    securityContext:
      runAsNonRoot: true
      runAsUser: 10001
      readOnlyRootFilesystem: true
    ```

* **Varsayılan ServiceAccount Token Erişimini Kapatma:** Pod'ların istem dışı Kubernetes API'sine erişmesini engellemek için otomatik token eşleme kapatılmalıdır:

    ```yaml
    spec:
      automountServiceAccountToken: false
    ```

* **Ağ Yalıtımı (Network Policies):** Namespace'ler arası veya podlar arası trafiği varsayılan olarak engelleyen ve sadece izin verilen yollara izin veren NetworkPolicy kuralları uygulanmalıdır.
* **Sırların (Secrets) Şifrelenmesi:** etcd üzerindeki veriler (Secret nesneleri) diskte şifrelenmiş (Encryption at Rest) olarak saklanmalıdır.

---

## 4. Ölçeklendirme (Autoscaling)

* **HPA (Horizontal Pod Autoscaler):** CPU veya Bellek kullanımına göre otomatik pod yatay ölçeklendirmesi etkinleştirilmelidir.
* **KEDA (Kubernetes Event-driven Autoscaling):** RabbitMQ kuyruk boyutu, Kafka mesaj gecikmesi veya Prometheus metriklerine göre ölçeklenme gerekiyorsa KEDA kullanılmalıdır.
* **Karpenter / Cluster Autoscaler:** Düğümlerin yük durumuna göre fiziksel/sanal sunucu sayısının otomatik artırılıp azaltılması sağlanmalıdır. Karpenter, hızlı düğüm açılış süreleri sunduğu için tercih edilmelidir.

---

## 5. Depolama Yönetimi (Storage)

* **Dinamik İstihsis (Dynamic Provisioning):** Manuel PV oluşturmak yerine, depolama sınıfları (StorageClass) üzerinden dinamik PVC yönetimi yapılmalıdır.
* **etcd Disk Performansı:** etcd'nin kurulu olduğu disklerin yüksek IOPS değerli (tercihen SSD/NVMe) olması ve gecikme süresinin 10ms'nin altında kalması sağlanmalıdır.

---

## 6. Gözlemlenebilirlik (Observability)

* **Merkezi Metrik Toplama:** Prometheus Operator aracılığıyla tüm küme ve uygulama metrikleri toplanmalı ve Grafana panelleri üzerinden takip edilmelidir.
* **Merkezi Loglama:** Pod logları lokal diskte biriktirilmeden, Fluent Bit veya Loki Agent'ları ile anlık olarak merkezi bir log deposuna (Loki, Elasticsearch) aktarılmalıdır. Log döndürme (log rotation) hem Docker/containerd düzeyinde hem de OS düzeyinde ayarlanmış olmalıdır.
* **Denetim Günlükleri (Audit Logging):** Kümedeki kritik API çağrılarını kimin yaptığını izlemek için Kubernetes Audit Log mekanizması etkinleştirilmelidir.

---

## 7. CI/CD ve GitOps En İyi Pratikleri

* **İmaj Etiketleme (Image Tagging):** Canlı dağıtımlarda asla `:latest` etiketi kullanılmamalıdır. Bunun yerine benzersiz Git Commit SHA'sı veya semantik versiyonlama (Örn: `v1.2.3-sha8f21`) tercih edilmelidir.
* **GitOps Modeli:** ArgoCD veya Flux v2 ile küme durumu Git deposundaki bildirimsel tanımlarla sürekli senkronize edilmelidir. Kümeye doğrudan erişimler (kubectl apply) kısıtlanmalıdır.
* **Sola Kaydırma (Shift-Left) Güvenliği:** Konteyner imajları CI/CD boru hattı içerisinde Trivy veya Clair gibi araçlarla güvenlik taramasından geçirildikten sonra kayıt defterine (Registry) yüklenmelidir.

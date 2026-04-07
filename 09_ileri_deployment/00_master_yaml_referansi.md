# Kubernetes Master YAML Referansı (Türkçe Açıklamalı)

Bu rehber, Kubernetes objelerinin (Pod, Deployment, Service, Ingress vb.) tüm önemli alanlarını ve bu alanların ne işe yaradığını satır satır Türkçe açıklamalarla sunar. 2026 yılı üretim (production) standartlarına ve v1.32+ API sürümlerine göre hazırlanmıştır.

---

## 📋 İçindekiler

1. [Pod](#1-pod) - Temel çalışma birimi
2. [Deployment](#2-deployment) - Stateless uygulama dağıtımı
3. [StatefulSet](#3-statefulset) - Stateful uygulama (DB, Queue)
4. [DaemonSet](#4-daemonset) - Her node'da pod
5. [Job](#5-job) - Tekil görev
6. [CronJob](#6-cronjob) - Zamanlanmış görev
7. [Service](#7-service) - LoadBalancer, NodePort, ClusterIP
8. [Ingress](#8-ingress) - HTTP routing & TLS
9. [NetworkPolicy](#9-networkpolicy) - Ağ güvenlik kuralları
10. [ConfigMap](#10-configmap) - Yapılandırma dosyaları
11. [Secret](#11-secret) - Şifreler & Sertifikalar
12. [PersistentVolume & PVC](#12-persistentvolume--persistentvolumeclaim) - Kalıcı depolama
13. [StorageClass](#13-storageclass) - Dinamik depolama
14. [RBAC](#14-rbac-serviceaccount-role-rolebinding) - Kimlik & Yetkilendirme
15. [PodDisruptionBudget](#15-poddisruptionbudget) - High-availability koruması
16. [Resource Management](#16-resource-management) - Quota, LimitRange, HPA, VPA
17. [Namespace](#17-namespace) - İzolasyon & Güvenlik (PSA)

---

## 1. Pod

```yaml
apiVersion: v1                        # ---> Kaynak Türü (API Versiyonu)
kind: Pod                             # ---> Obje Tipi (Bu dosyada POD)
metadata:
  name: techops-pod                   # ---> Pod için benzersiz isim
  labels:                             # ---> Pod'ları organize etmek ve seçmek için etiketler
    app: techops                      # ---> Uygulama etiketi (Service/Deployment seçicileri için)
    tier: backend                     # ---> Uygulama katmanını tanımlamak için
  annotations:                        # ---> [OPSİYONEL] İzleme araçları veya notlar için veri
    "prometheus.io/scrape": "true"    # ---> Prometheus bu podu izlesin

spec:
  # --- 1. GENEL AYARLAR ---
  restartPolicy: Always               # ---> Pod yeniden başlatma ilkesi (Always, OnFailure, Never)
  serviceAccountName: backend-sa      # ---> [OPSİYONEL] API yetkileri için kimlik (RBAC)
  automountServiceAccountToken: false # ---> [OPSİYONEL] Güvenlik için token mount etme (API erişimi yoksa)
  terminationGracePeriodSeconds: 30   # ---> [OPSİYONEL] Kapanırken (SIGTERM) uygulamanın bitirmesi için tanınan süre
  priorityClassName: high-priority    # ---> [OPSİYONEL] Önemli Pod (Yer yoksa diğerlerini siler)
  imagePullSecrets:                   # ---> [OPSİYONEL] Özel (Private) Registry şifresi
  - name: my-registry-key

  # --- 2. ZAMANLAMA VE YERLEŞİM (SCHEDULING) ---
  nodeSelector:                       # ---> Pod'u belirli sunuculara yönlendirme
    disktype: ssd                     # ---> Sadece "disktype=ssd" etiketli Node'larda çalış

  tolerations:                        # ---> "Lekeli" (Tainted) Node'larda çalışabilme izni
  - key: "special-taint"              # ---> Tolerans gösterilecek Taint anahtarı
    operator: "Equal"                 # ---> Eşleşme türü
    value: "true"                     # ---> Değer
    effect: "NoExecute"               # ---> Etki

  affinity:                           # ---> [OPSİYONEL] Gelişmiş Yerleşim Kuralları
    podAntiAffinity:                  # ---> [OPSİYONEL] Yedeklilik: Aynı uygulamanın yanına gitme
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions: [{key: app, operator: In, values: ["techops"]}]
          topologyKey: kubernetes.io/hostname

  topologySpreadConstraints:          # ---> [OPSİYONEL] Zone'lara (Veri Merkezlerine) eşit dağıt
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels: { app: techops }

  # --- 3. AĞ VE DNS ---
  hostNetwork: false                  # ---> [OPSİYONEL] Host ağını kullanma (Varsayılan false, güvenlik için önemli)
  enableServiceLinks: false           # ---> [OPSİYONEL] Gereksiz env variable'ları devre dışı bırak (Performans)
  shareProcessNamespace: false        # ---> [OPSİYONEL] Container'lar arası process görünürlüğü (Sidecar için true yapılabilir)
  dnsPolicy: ClusterFirst             # ---> [OPSİYONEL] DNS politikası (ClusterFirst, Default, None)
  dnsConfig:                          # ---> [OPSİYONEL] Özel DNS ayarları
    options:
    - name: ndots                     # ---> DNS çözümleme hassasiyeti
      value: "2"

  hostAliases:                        # ---> [OPSİYONEL] /etc/hosts dosyasına ekleme
  - ip: "10.0.0.5"
    hostnames: ["db.local"]

  # --- 4. POD GÜVENLİĞİ ---
  securityContext:                    # ---> Pod düzeyinde güvenlik ayarları
    runAsUser: 1000                   # ---> User ID 1000 (Root Değil)
    runAsGroup: 3000                  # ---> Group ID 3000
    fsGroup: 2000                     # ---> Disklerin grup sahipliği
    seccompProfile:                   # ---> [OPSİYONEL] Kernel system call filtreleme
      type: RuntimeDefault            # ---> RuntimeDefault, Localhost, veya Unconfined

  # --- 5. KONTEYNERLER ---
  containers:                         # ---> Bu Pod içinde çalışan konteynerler listesi
  
  # A) Ana Konteyner
  - name: techops-container           # ---> Konteynerin adı
    image: nginx:1.23                 # ---> Konteyner için kullanılacak Docker imajı
    imagePullPolicy: IfNotPresent     # ---> [OPSİYONEL] İmajı ne zaman çekecek (Always, IfNotPresent, Never)
    ports:
    - name: http                      # ---> [OPSİYONEL] Port ismi (Service selector için)
      containerPort: 80               # ---> Konteynerin dışarı açtığı port
      protocol: TCP                   # ---> [OPSİYONEL] Protokol (TCP/UDP/SCTP)
    
    env:                              # ---> Konteyner içine aktarılacak ortam değişkenleri
    - name: ENV
      value: production

    # [OPSİYONEL] Kaynak Limitleri (Canlı Ortam Şartı)
    resources:                        # ---> CPU/RAM/Disk Kullanımı
      requests:                       # ---> Garanti edilen kaynak
        cpu: "500m"                   # ---> Yarım çekirdek
        memory: "128Mi"               # ---> 128 MB RAM
        ephemeral-storage: "1Gi"      # ---> [OPSİYONEL] Log/geçici dosyalar için disk
      limits:                         # ---> Tavan limit
        cpu: "1"                      # ---> 1 çekirdek
        memory: "256Mi"               # ---> 256 MB RAM
        ephemeral-storage: "2Gi"      # ---> [OPSİYONEL] Disk dolarsa Pod evict edilir

    # [OPSİYONEL] Sağlık Kontrolleri
    startupProbe:                     # ---> [OPSİYONEL] Yavaş açılan uygulamalar için ilk kontrol
      httpGet: { path: /healthz, port: 80 }
      failureThreshold: 30            # ---> 30 deneme hakkı
      periodSeconds: 10               # ---> [OPSİYONEL] Kontrol sıklığı
      timeoutSeconds: 3               # ---> [OPSİYONEL] Cevap bekleme süresi
    
    livenessProbe:                    # ---> "Uygulama yaşıyor mu?" (Çökerse Restart)
      httpGet: { path: /healthz, port: 80 }
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 3
    
    readinessProbe:                   # ---> "Trafik almaya hazır mı?" (Yük gelmesin)
      tcpSocket: { port: 80 }
      periodSeconds: 5
      timeoutSeconds: 2

    # [OPSİYONEL] Yaşam Döngüsü (Graceful Shutdown)
    lifecycle:
      preStop:                        # ---> Kapanmadan hemen önce çalışacak komut
        exec: { command: ["/usr/sbin/nginx", "-s", "quit"] }

    # [OPSİYONEL] Güvenlik (Container Seviyesi)
    securityContext:
      readOnlyRootFilesystem: true    # ---> Dosya sistemini yazmaya kapat
      runAsNonRoot: true              # ---> [OPSİYONEL] Root kullanıcı ile çalışmayı engelle
      capabilities:                   # ---> Linux Kernel yetkilerini kısıtla
        drop: ["ALL"]
        add: ["NET_BIND_SERVICE"]     # ---> Sadece port açmaya izin ver

    volumeMounts:                     # ---> Disk birimi bağlama ayarları
    - name: config-volume             # ---> Disk ismi
      mountPath: /usr/share/nginx/html # ---> Hedef yol (HTML dosyaları için)
    # [ZORUNLU] ReadOnlyRootFilesystem için yazılabilir alanlar:
    - name: tmp-cache                 
      mountPath: /var/cache/nginx
    - name: tmp-pid                   # ---> Nginx'in PID dosyası yazabilmesi için
      mountPath: /var/run
    - name: shared-logs               # ---> [OPSİYONEL] Logları buraya yaz ki Sidecar okusun
      mountPath: /var/log/nginx

  # B) [OPSİYONEL] Sidecar Konteyner (Log Shipper)
  - name: log-shipper                 # ---> Ana uygulamanın yanında çalışan yardımcı
    image: busybox
    args: ["/bin/sh", "-c", "tail -n0 -F /shared/access.log 2>/dev/null || sleep infinity"] # ---> Paylaşılan logu oku
    resources:
      requests: { cpu: "100m", memory: "64Mi" }
      limits: { cpu: "200m", memory: "128Mi" }
    volumeMounts:
    - name: shared-logs               # ---> Ana konteyner ile aynı diski bağla
      mountPath: /shared              # ---> Buradaki /shared, ana kaptaki /var/log/nginx ile aynı yer

  # --- 6. DEPOLAMA (VOLUMES) ---
  volumes:                            # ---> Pod'a tanımlanan disk kaynakları
  - name: config-volume               # ---> ConfigMap kaynağı
    configMap:
      name: techops-config
  - name: tmp-cache                   # ---> Geçici Disk (Cache)
    emptyDir: {}
  - name: tmp-pid                     # ---> Geçici Disk (PID)
    emptyDir: {}
  - name: shared-logs                 # ---> [OPSİYONEL] Sidecar ile paylaşılan disk
    emptyDir: {}

  # --- 7. BAŞLANGIÇ (INIT) ---
  initContainers:                     # ---> Ana konteynerlerden ÖNCE çalışıp kapananlar
  - name: init-techops                # ---> Başlangıç konteynerinin adı
    image: busybox                    # ---> İmaj
    command: ["sh", "-c", "sleep 5"]  # ---> Hazırlık komutu
    resources:                        # ---> [ZORUNLU] InitContainer için kaynak limitleri
      requests:
        cpu: "50m"
        memory: "32Mi"
      limits:
        cpu: "100m"
        memory: "64Mi"
```

---

## 2. Deployment

```yaml
apiVersion: apps/v1                   # ---> Deployment için API versiyonu (apps/v1)
kind: Deployment                      # ---> Deployment objesi
metadata:
  name: nginx-deployment              # ---> Deployment adı
  labels:
    app: nginx                        # ---> Deployment etiketleri
spec:
  replicas: 3                         # ---> Kaç Pod çalışacak
  revisionHistoryLimit: 10            # ---> [OPSİYONEL] Kaç eski versiyon saklanacak (Rollback için)
  
  selector:                           # ---> Hangi Pod'ları yöneteceğini belirler
    matchLabels:                      # ---> Pod template'teki labels ile AYNI OLMALI
      app: nginx
  
  strategy:                           # ---> Güncelleme stratejisi
    type: RollingUpdate               # ---> Sıfır downtime update (Recreate alternatifi)
    rollingUpdate:
      maxSurge: 1                     # ---> Update sırasında fazladan kaç pod olabilir
      maxUnavailable: 0               # ---> Update sırasında kaç pod kapanabilir
  
  template:                           # ---> Pod şablonu (burası Pod spec ile aynı)
    metadata:
      labels:                         # ---> Pod etiketleri (selector ile eşleşmeli)
        app: nginx
        tier: frontend                # ---> [OPSİYONEL] NetworkPolicy için katman etiketi (Frontend)
        version: "1.23"               # ---> [OPSİYONEL] Versiyon takibi için
    spec:
      containers:
      - name: nginx
        image: nginx:1.23             # ---> Container imajı
        ports:
        - name: http
          containerPort: 80
          protocol: TCP
        resources:                    # ---> [ZORUNLU] Production için
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:                # ---> Sağlık kontrolü
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:               # ---> Trafik hazırlığı
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
```

---

## 3. StatefulSet

```yaml
apiVersion: apps/v1                   # ---> StatefulSet için API
kind: StatefulSet                     # ---> StatefulSet objesi
metadata:
  name: postgres-sts                  # ---> StatefulSet adı
spec:
  serviceName: postgres-headless      # ---> [ZORUNLU] Headless Service adı (DNS için)
  replicas: 3                         # ---> Kaç replica (postgres-sts-0, -1, -2)
  
  updateStrategy:                     # ---> [OPSİYONEL] Güncelleme stratejisi
    type: RollingUpdate               # ---> RollingUpdate veya OnDelete
    rollingUpdate:
      partition: 0                    # ---> İlk N pod güncellenmez (0 = hepsi güncellensin)
  
  selector:
    matchLabels:
      app: postgres
  
  template:
    metadata:
      labels:
        app: postgres
        tier: database                # ---> [OPSİYONEL] NetworkPolicy için katman etiketi (DB)
    spec:
      containers:
      - name: postgres
        image: postgres:15            # ---> PostgreSQL imajı
        ports:
        - name: postgres
          containerPort: 5432
          protocol: TCP
        
        startupProbe:                 # ---> [OPSİYONEL] DB'nin açılması zaman alabilir
          exec:
            command: ["pg_isready", "-U", "postgres"]
          failureThreshold: 30
          periodSeconds: 10
        
        livenessProbe:                # ---> [OPSİYONEL] DB yaşıyor mu?
          exec:
            command: ["pg_isready", "-U", "postgres"]
          initialDelaySeconds: 30
          periodSeconds: 10
        
        readinessProbe:               # ---> [OPSİYONEL] DB sorgu kabul ediyor mu?
          exec:
            command: ["pg_isready", "-U", "postgres"]
          initialDelaySeconds: 5
          periodSeconds: 5
 
        env:                          # ---> Veritabanı config
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        - name: PGDATA              # ---> Data dizini (PVC mount yolu)
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgres-storage      # ---> PVC mount
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
  
  # [ZORUNLU] Volume Claim Templates - Her pod için ayrı PVC oluşturur
  volumeClaimTemplates:               # ---> Dinamik PVC oluşturma
  - metadata:
      name: postgres-storage          # ---> PVC adı (postgres-storage-postgres-sts-0)
    spec:
      accessModes: ["ReadWriteOnce"]  # ---> Tek node yazabilir
      storageClassName: fast-ssd      # ---> StorageClass adı
      resources:
        requests:
          storage: 10Gi               # ---> Disk boyutu
---
# [GEREKLİ] Headless Service - DNS için stabil network ID
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless             # ---> serviceName ile aynı
spec:
  clusterIP: None                     # ---> Headless (IP yok, sadece DNS)
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

---

## 4. DaemonSet

```yaml
apiVersion: apps/v1                   # ---> DaemonSet için API
kind: DaemonSet                       # ---> DaemonSet objesi
metadata:
  name: node-exporter                 # ---> DaemonSet adı
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  
  updateStrategy:                     # ---> Güncelleme stratejisi
    type: RollingUpdate               # ---> Node'lar sırayla güncellenir
    rollingUpdate:
      maxUnavailable: 1               # ---> Aynı anda kaç node güncellenebilir
  
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true               # ---> [OPSİYONEL] Host network kullan (Metrics toplama için)
      hostPID: true                   # ---> [OPSİYONEL] Host process'leri gör
      
      tolerations:                    # ---> Master node'da da çalışabilsin
      - key: node-role.kubernetes.io/control-plane  # ---> Modern Kubernetes (1.20+)
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master         # ---> [OPSİYONEL] Eski cluster'lar için
        operator: Exists
        effect: NoSchedule
      
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        args:                         # ---> Prometheus Node Exporter parametreleri
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        ports:
        - name: metrics
          containerPort: 9100
          protocol: TCP
        volumeMounts:                 # ---> Host dosya sistemi erişimi
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        resources:
          requests:
            cpu: "100m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
      
      volumes:                        # ---> Host volume'lar
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
```

---

## 5. Job

```yaml
apiVersion: batch/v1                  # ---> Job için API (batch/v1)
kind: Job                             # ---> Job objesi
metadata:
  name: database-backup               # ---> Job adı
spec:
  ttlSecondsAfterFinished: 3600       # ---> [OPSİYONEL] Job tamamlandıktan 1 saat sonra sil
  backoffLimit: 3                     # ---> Kaç kez hata sonrası yeniden dener
  completions: 1                      # ---> Kaç başarılı pod gerekli
  parallelism: 1                      # ---> Aynı anda kaç pod çalışabilir
  
  template:
    metadata:
      labels:
        job: database-backup
    spec:
      restartPolicy: OnFailure        # ---> [ZORUNLU] Job için (Never veya OnFailure)
      containers:
      - name: backup
        image: postgres:15
        command:                      # ---> Backup komutu
        - /bin/sh
        - -c
        - |
          pg_dump -h postgres-service -U admin -d mydb > /backup/db-$(date +%Y%m%d).sql
          echo "Backup completed"
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        volumeMounts:
        - name: backup-storage
          mountPath: /backup
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
      volumes:
      - name: backup-storage
        persistentVolumeClaim:
          claimName: backup-pvc
```

---

## 6. CronJob

```yaml
apiVersion: batch/v1                  # ---> CronJob için API
kind: CronJob                         # ---> CronJob objesi
metadata:
  name: nightly-cleanup               # ---> CronJob adı
spec:
  schedule: "0 2 * * *"               # ---> Cron syntax: Her gece 02:00
                                      # ---> Format: dakika saat gün ay haftanınGünü
  concurrencyPolicy: Forbid           # ---> Aynı anda çalışan job'ları engelle (Allow, Forbid, Replace)
  successfulJobsHistoryLimit: 3       # ---> Kaç başarılı job saklanacak
  failedJobsHistoryLimit: 1           # ---> Kaç başarısız job saklanacak
  
  jobTemplate:                        # ---> Job template (Job spec ile aynı)
    spec:
      ttlSecondsAfterFinished: 7200   # ---> 2 saat sonra sil
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: cleanup
            image: busybox
            command:
            - /bin/sh
            - -c
            - |
              echo "Cleaning old logs..."
              find /logs -type f -mtime +7 -delete
              echo "Cleanup completed at $(date)"
            volumeMounts:
            - name: logs
              mountPath: /logs
            resources:
              requests:
                cpu: "100m"
                memory: "64Mi"
              limits:
                cpu: "200m"
                memory: "128Mi"
          volumes:
          - name: logs
            hostPath:
              path: /var/log/app
              type: DirectoryOrCreate
```

---

## 7. Service

```yaml
# [TİP 1] ClusterIP - Varsayılan, sadece Cluster içi erişim
apiVersion: v1
kind: Service
metadata:
  name: nginx-clusterip             # ---> Service adı
spec:
  type: ClusterIP                     # ---> Cluster içi IP (Dışardan erişim yok)
  sessionAffinity: ClientIP           # ---> [OPSİYONEL] Sticky sessions (aynı client = aynı pod)
  sessionAffinityConfig:              # ---> [OPSİYONEL] Session ayarları
    clientIP:
      timeoutSeconds: 10800           # ---> 3 saat
  selector:                           # ---> Hangi Pod'lara trafik gidecek
    app: nginx
  ports:
  - name: http                        # ---> Port adı
    protocol: TCP                     # ---> Protokol
    port: 80                          # ---> Service'in dinlediği port
    targetPort: http                  # ---> [OPSİYONEL] Named port kullanımı (Pod'daki port ismi)
  - name: https                       # ---> [OPSİYONEL] Multiple port
    protocol: TCP
    port: 443
    targetPort: 443
---
# [TİP 2] NodePort - Cluster dışından erişim (NodeIP:NodePort)
apiVersion: v1
kind: Service
metadata:
  name: nginx-nodeport
spec:
  type: NodePort                      # ---> Her node'da port açar
  selector:
    app: nginx
  ports:
  - name: http
    protocol: TCP
    port: 80                          # ---> Service port (Cluster içi)
    targetPort: http                  # ---> [OPSİYONEL] Named port kullanımı (Pod'daki port ismi)
    nodePort: 30080                   # ---> [OPSİYONEL] Node üzerindeki port (30000-32767), boş bırakılırsa otomatik
---
# [TİP 3] LoadBalancer - Cloud provider load balancer (AWS ELB, GCP LB)
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
  annotations:                        # ---> [OPSİYONEL] Cloud-specific annotations
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
spec:
  type: LoadBalancer                  # ---> Cloud LB oluşturur
  externalTrafficPolicy: Local        # ---> [OPSİYONEL] Local (kaynak IP korunur) veya Cluster
  selector:
    app: nginx
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: http                  # ---> [OPSİYONEL] Named port kullanımı (Pod'daki port ismi)
  loadBalancerSourceRanges:           # ---> [OPSİYONEL] Hangi IP'ler erişebilir
  - "203.0.113.0/24"
---
# [TİP 4] Headless Service - StatefulSet için (IP yok, sadece DNS)
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None                     # ---> Headless (DNS adresleri verir ama ClusterIP yok)
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

---

## 8. Ingress

```yaml
apiVersion: networking.k8s.io/v1      # ---> Ingress API
kind: Ingress                         # ---> Ingress objesi
metadata:
  name: multi-domain-ingress          # ---> Ingress adı
  annotations:                        # ---> [OPSİYONEL] Ingress controller'a özel ayarlar
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # ---> [OPSİYONEL] Otomatik SSL (cert-manager)
spec:
  ingressClassName: nginx             # ---> [OPSİYONEL] Hangi Ingress controller (nginx, traefik, haproxy)
  
  tls:                                # ---> HTTPS / TLS yapılandırması
  - hosts:
    - www.example.com
    - api.example.com
    secretName: example-tls-cert      # ---> TLS sertifikası (Secret objesi)
  
  rules:                              # ---> Routing kuralları
  # [KURAL 1] www.example.com -> frontend servisi
  - host: www.example.com             # ---> Domain adı
    http:
      paths:
      - path: /                       # ---> URL path
        pathType: Prefix              # ---> Prefix (/, /api gibi) veya Exact (/login tam eşleşme)
        backend:
          service:
            name: nginx-clusterip     # ---> Hedef Service adı
            port:
              number: 80              # ---> Service port
  
  # [KURAL 2] api.example.com -> backend servisi (Path-based routing)
  - host: api.example.com
    http:
      paths:
      - path: /v1                     # ---> /v1/* -> backend-v1-service
        pathType: Prefix
        backend:
          service:
            name: backend-v1-service
            port:
              number: 8080
      - path: /v2                     # ---> /v2/* -> backend-v2-service
        pathType: Prefix
        backend:
          service:
            name: backend-v2-service
            port:
              number: 8080
```

---

## 9. NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1      # ---> NetworkPolicy API
kind: NetworkPolicy                   # ---> NetworkPolicy objesi
metadata:
  name: backend-isolation             # ---> Policy adı
  namespace: production               # ---> Hangi namespace
spec:
  podSelector:                        # ---> Hangi Pod'lara uygulanacak
    matchLabels:
      tier: backend
  
  policyTypes:                        # ---> Hangi yönde kural var
  - Ingress                           # ---> Gelen trafik kuralları
  - Egress                            # ---> Giden trafik kuralları
  
  ingress:                            # ---> GİRİŞ kuralları (Kimler bu pod'a erişebilir)
  - from:                             # ---> Kaynak #1: Frontend pod'ları
    - podSelector:
        matchLabels:
          tier: frontend
    ports:                            # ---> Hangi portlara
    - protocol: TCP
      port: 8080
  
  - from:                             # ---> Kaynak #2: Monitoring namespace'inden gelen trafik
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9090
  
  egress:                             # ---> ÇIKIŞ kuralları (Bu pod nerelere erişebilir)
  - to:                               # ---> Hedef #1: Database pod'ları
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 5432
  
  - to:                               # ---> Hedef #2: Dış DNS sorguları
    - namespaceSelector: {}           # ---> Tüm namespace'ler
    ports:
    - protocol: UDP
      port: 53
  
  - to:                               # ---> Hedef #3: Dış API (IP bazlı)
    - ipBlock:
        cidr: 10.0.0.0/16             # ---> İzin verilen IP aralığı
        except:                       # ---> Hariç tutulan IP'ler
        - 10.0.1.0/24
```

---

## 10. ConfigMap

```yaml
apiVersion: v1                        # ---> ConfigMap API
kind: ConfigMap                       # ---> ConfigMap objesi
metadata:
  name: nginx-config                  # ---> ConfigMap adı
data:                                 # ---> Key-value çiftleri
  # [Basit değerler]
  LOG_LEVEL: "info"                   # ---> String değer
  MAX_CONNECTIONS: "100"              # ---> Sayısal değer (string olarak)
  
  # [Dosya içeriği] - nginx.conf dosyası
  nginx.conf: |                       # ---> Multi-line dosya (| ile)
    server {
      listen 80;
      server_name localhost;
      
      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
      
      location /api {
        proxy_pass http://backend-service:8080;
      }
    }
  
  # [JSON/YAML dosya]
  config.json: |
    {
      "database": {
        "host": "postgres-service",
        "port": 5432
      }
    }
---
# [KULLANIM 1] Environment Variable olarak
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
spec:
  containers:
  - name: app
    image: myapp:latest
    env:
    - name: LOG_LEVEL                 # ---> Env variable adı
      valueFrom:
        configMapKeyRef:
          name: nginx-config          # ---> ConfigMap adı
          key: LOG_LEVEL              # ---> ConfigMap'teki key
    envFrom:                          # ---> [OPSİYONEL] Tüm key'leri env variable yap
    - configMapRef:
        name: nginx-config
---
# [KULLANIM 2] Volume olarak mount et
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.23
    volumeMounts:
    - name: config-volume
      mountPath: /etc/nginx/nginx.conf  # ---> Dosya yolu
      subPath: nginx.conf             # ---> ConfigMap'teki key adı
  volumes:
  - name: config-volume
    configMap:
      name: nginx-config              # ---> ConfigMap adı
```

---

## 11. Secret

```yaml
# [TİP 1] Opaque - Generic şifreler
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret               # ---> Secret adı
type: Opaque                          # ---> Generic secret type
data:                                 # ---> Base64 encoded değerler
  username: YWRtaW4=                  # ---> "admin" (echo -n "admin" | base64)
  password: cGFzc3dvcmQxMjM=          # ---> "password123"
---
# [TİP 2] TLS Certificate
apiVersion: v1
kind: Secret
metadata:
  name: tls-secret
type: kubernetes.io/tls               # ---> TLS secret type
data:
  tls.crt: LS0tLS1CRUdJTi...         # ---> Certificate (base64)
  tls.key: LS0tLS1CRUdJTi...         # ---> Private key (base64)
---
# [TİP 3] Docker Registry
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-secret
type: kubernetes.io/dockerconfigjson  # ---> Docker registry type
data:
  .dockerconfigjson: eyJhdXRocyI6...  # ---> Docker config JSON (base64)
---
# [KULLANIM 1] Environment Variable olarak
apiVersion: v1
kind: Pod
metadata:
  name: postgres-pod
spec:
  containers:
  - name: postgres
    image: postgres:15
    env:
    - name: POSTGRES_USER             # ---> Env variable adı
      valueFrom:
        secretKeyRef:
          name: postgres-secret       # ---> Secret adı
          key: username               # ---> Secret key
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
          name: postgres-secret
          key: password
---
# [KULLANIM 2] Volume olarak mount et
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
spec:
  containers:
  - name: app
    image: myapp
    volumeMounts:
    - name: secret-volume
      mountPath: /etc/secrets         # ---> Mount yolu
      readOnly: true                  # ---> [ÖNEMLİ] Read-only yap
  volumes:
  - name: secret-volume
    secret:
      secretName: postgres-secret     # ---> Secret adı
      defaultMode: 0400               # ---> [OPSİYONEL] File permissions (read-only owner)
---
# [KULLANIM 3] ImagePullSecrets
apiVersion: v1
kind: Pod
metadata:
  name: private-image-pod
spec:
  containers:
  - name: app
    image: myregistry.com/myapp:latest
  imagePullSecrets:                   # ---> Private registry için
  - name: dockerhub-secret
```

---

## 12. PersistentVolume & PersistentVolumeClaim

```yaml
# [ADIM 1] PersistentVolume - Cluster admin tarafından oluşturulur
apiVersion: v1
kind: PersistentVolume                # ---> PV objesi
metadata:
  name: nfs-pv                        # ---> PV adı
spec:
  capacity:
    storage: 10Gi                     # ---> Depolama boyutu
  
  accessModes:                        # ---> Erişim modu
  - ReadWriteMany                     # ---> RWX: Çok pod okuyup yazabilir
                                      # ---> RWO: Tek pod yazabilir (ReadWriteOnce)
                                      # ---> ROX: Çok pod sadece okuyabilir (ReadOnlyMany)
  
  persistentVolumeReclaimPolicy: Retain  # ---> PVC silinince ne olacak
                                      # ---> Retain: PV kalır (manuel temizlik)
                                      # ---> Delete: PV otomatik silinir
                                      # ---> Recycle: Data silinir, PV yeniden kullanılır (deprecated)
  
  storageClassName: nfs-storage       # ---> [OPSİYONEL] StorageClass adı (PVC ile eşleşmeli)
  
  nfs:                                # ---> NFS backend
    server: 192.168.1.100             # ---> NFS server IP
    path: "/exports/data"             # ---> NFS export path
---
# [ADIM 2] PersistentVolumeClaim - User tarafından oluşturulur
apiVersion: v1
kind: PersistentVolumeClaim           # ---> PVC objesi
metadata:
  name: nfs-pvc                       # ---> PVC adı
spec:
  accessModes:                        # ---> PV ile uyumlu olmalı
  - ReadWriteMany
  
  resources:
    requests:
      storage: 5Gi                    # ---> İstenen boyut (PV'den küçük veya eşit)
  
  storageClassName: nfs-storage       # ---> PV ile aynı StorageClass
  
  # [OPSİYONEL] Selector - Spesifik PV seçimi
  selector:
    matchLabels:
      environment: production
---
# [ADIM 3] Pod'ta kullan
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data-volume
      mountPath: /data                # ---> Container içi path
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: nfs-pvc              # ---> PVC adı
```

---

## 13. StorageClass

```yaml
apiVersion: storage.k8s.io/v1         # ---> StorageClass API
kind: StorageClass                    # ---> StorageClass objesi
metadata:
  name: fast-ssd                      # ---> StorageClass adı
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"  # ---> [OPSİYONEL] Varsayılan SC mi?
provisioner: kubernetes.io/aws-ebs    # ---> Depolama sağlayıcı
                                      # ---> AWS: kubernetes.io/aws-ebs
                                      # ---> GCP: kubernetes.io/gce-pd
                                      # ---> Azure: kubernetes.io/azure-disk
                                      # ---> Local: kubernetes.io/no-provisioner
parameters:                           # ---> Provisioner'a özel parametreler
  type: gp3                           # ---> AWS EBS type (gp2, gp3, io1, io2)
  iopsPerGB: "10"                     # ---> IOPS (I/O per second)
  fsType: ext4                        # ---> Dosya sistemi
  encrypted: "true"                   # ---> Şifreli disk
reclaimPolicy: Delete                 # ---> PVC silinince PV ne olacak (Delete, Retain)
volumeBindingMode: WaitForFirstConsumer  # ---> Ne zaman PV oluşturulacak
                                      # ---> Immediate: PVC oluşturulunca hemen
                                      # ---> WaitForFirstConsumer: Pod oluşturulunca (zone awareness için)
allowVolumeExpansion: true            # ---> [OPSİYONEL] PVC boyutu artırılabilir mi
---
# [KULLANIM] PVC oluştururken StorageClass kullan
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: fast-ssd          # ---> Bu StorageClass kullanılacak
  resources:
    requests:
      storage: 20Gi
```

---

## 14. RBAC (ServiceAccount, Role, RoleBinding)

```yaml
# [ADIM 1] ServiceAccount - Pod'un kimliği
apiVersion: v1
kind: ServiceAccount                  # ---> ServiceAccount objesi
metadata:
  name: backend-sa                    # ---> ServiceAccount adı
  namespace: production
automountServiceAccountToken: false   # ---> [OPSİYONEL] Token otomatik mount edilmesin (güvenlik)
---
# [ADIM 2] Role - Namespace-scoped izinler
apiVersion: rbac.authorization.k8s.io/v1
kind: Role                            # ---> Role objesi (namespace içi)
metadata:
  name: pod-reader                    # ---> Role adı
  namespace: production
rules:                                # ---> İzin kuralları
- apiGroups: [""]                     # ---> Core API group (Pod, Service, ConfigMap)
  resources: ["pods"]                 # ---> Hangi kaynaklara
  verbs: ["get", "list", "watch"]     # ---> Hangi işlemler
                                      # ---> get: Tekil okuma
                                      # ---> list: Listeleme
                                      # ---> watch: Değişiklikleri izleme
                                      # ---> create, update, patch, delete
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get"]
---
# [ADIM 3] RoleBinding - Role'u ServiceAccount'a bağla
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding                     # ---> RoleBinding objesi
metadata:
  name: backend-pod-reader            # ---> Binding adı
  namespace: production
subjects:                             # ---> Kime (user, group, serviceaccount)
- kind: ServiceAccount
  name: backend-sa                    # ---> ServiceAccount adı
  namespace: production
roleRef:                              # ---> Hangi Role
  kind: Role
  name: pod-reader                    # ---> Role adı
  apiGroup: rbac.authorization.k8s.io
---
# [KULLANIM] Pod'ta ServiceAccount kullan
apiVersion: v1
kind: Pod
metadata:
  name: backend-pod
  namespace: production
spec:
  serviceAccountName: backend-sa      # ---> Bu ServiceAccount'u kullan
  containers:
  - name: app
    image: myapp
```

**ClusterRole & ClusterRoleBinding** (Cluster-wide):

```yaml
# Tüm namespace'lerde geçerli izinler
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole                     # ---> Cluster-wide Role
metadata:
  name: cluster-pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes"]                # ---> Node gibi cluster-level kaynaklar
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding              # ---> Cluster-wide Binding
metadata:
  name: cluster-reader-binding
subjects:
- kind: ServiceAccount
  name: backend-sa
  namespace: production
roleRef:
  kind: ClusterRole
  name: cluster-pod-reader
  apiGroup: rbac.authorization.k8s.io
```

---

## 15. PodDisruptionBudget

```yaml
apiVersion: policy/v1                 # ---> PodDisruptionBudget API
kind: PodDisruptionBudget             # ---> PDB objesi
metadata:
  name: nginx-pdb                     # ---> PDB adı
spec:
  minAvailable: 2                     # ---> En az 2 pod ayakta kalmalı
                                      # ---> Alternatif: maxUnavailable: 1 (aynı anda en fazla 1 pod down)
  selector:                           # ---> Hangi Pod'ları koruyacak
    matchLabels:
      app: nginx
---
# [ÖRNEK 2] Yüzde bazlı PDB
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
1111: spec:
1112:   minAvailable: 50%                   # ---> Pod'ların %50'si ayakta kalmalı
1113:   selector:
1114:     matchLabels:
1115:       tier: backend
```

---

## 16. Resource Management

### PriorityClass

```yaml
apiVersion: scheduling.k8s.io/v1      # ---> PriorityClass API
kind: PriorityClass                   # ---> PriorityClass objesi
metadata:
  name: high-priority                 # ---> PriorityClass adı (Pod'da referans edilir)
value: 1000000                        # ---> Öncelik değeri (yüksek = daha öncelikli)
                                      # ---> Varsayılan sistem pod'ları: 2000000000
                                      # ---> Kullanıcı pod'ları için önerilen: 0 - 1000000
globalDefault: false                  # ---> [OPSİYONEL] Varsayılan PriorityClass mi?
preemptionPolicy: PreemptLowerPriority  # ---> [OPSİYONEL] Düşük öncelikli pod'ları çıkarabilir mi
                                      # ---> PreemptLowerPriority (varsayılan) veya Never
description: "Kritik iş yükleri için yüksek öncelik"  # ---> [OPSİYONEL] Açıklama
---
# [ÖRNEK 2] Düşük öncelikli batch job'lar için
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
preemptionPolicy: Never               # ---> Başka pod'ları çıkartma
description: "Batch işler için düşük öncelik"
```

### ResourceQuota

```yaml
apiVersion: v1
kind: ResourceQuota                   # ---> ResourceQuota objesi
metadata:
  name: dev-quota                     # ---> Quota adı
  namespace: development
spec:
  hard:                               # ---> Limitler
    requests.cpu: "10"                # ---> Toplam CPU request (10 core)
    requests.memory: "20Gi"           # ---> Toplam RAM request
    limits.cpu: "20"                  # ---> Toplam CPU limit
    limits.memory: "40Gi"             # ---> Toplam RAM limit
    persistentvolumeclaims: "10"      # ---> Maksimum PVC sayısı
    pods: "50"                        # ---> Maksimum Pod sayısı
    services: "20"                    # ---> Maksimum Service sayısı
    configmaps: "30"                  # ---> Maksimum ConfigMap sayısı
```

### LimitRange

```yaml
apiVersion: v1
kind: LimitRange                      # ---> LimitRange objesi
metadata:
  name: dev-limits                    # ---> LimitRange adı
  namespace: development
spec:
  limits:
  - type: Container                   # ---> Container limitleri
    default:                          # ---> Varsayılan limit (belirtilmezse)
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:                   # ---> Varsayılan request
      cpu: "200m"
      memory: "256Mi"
    max:                              # ---> Maksimum değer
      cpu: "2"
      memory: "2Gi"
    min:                              # ---> Minimum değer
      cpu: "100m"
      memory: "128Mi"
  
  - type: Pod                         # ---> Pod limitleri
    max:
      cpu: "4"
      memory: "4Gi"
  
  - type: PersistentVolumeClaim       # ---> PVC limitleri
    max:
      storage: "50Gi"
    min:
      storage: "1Gi"
```

### HorizontalPodAutoscaler (HPA)

```yaml
apiVersion: autoscaling/v2            # ---> HPA API v2
kind: HorizontalPodAutoscaler         # ---> HPA objesi
metadata:
  name: nginx-hpa                     # ---> HPA adı
spec:
  scaleTargetRef:                     # ---> Hangi kaynak ölçeklenecek
    apiVersion: apps/v1
    kind: Deployment                  # ---> Deployment, StatefulSet, ReplicaSet
    name: nginx-deployment
  
  minReplicas: 2                      # ---> Minimum pod sayısı
  maxReplicas: 10                     # ---> Maksimum pod sayısı
  
  metrics:                            # ---> Ölçeklendirme metrikleri
  - type: Resource
    resource:
      name: cpu                       # ---> CPU kullanımı
      target:
        type: Utilization
        averageUtilization: 70        # ---> %70 CPU kullanımında ölçeklendir
  
  - type: Resource
    resource:
      name: memory                    # ---> RAM kullanımı
      target:
        type: Utilization
        averageUtilization: 80        # ---> %80 RAM kullanımında ölçeklendir
  
  behavior:                           # ---> [OPSİYONEL] Ölçeklendirme davranışı
    scaleDown:
      stabilizationWindowSeconds: 300  # ---> Scale down için 5 dk bekle
      policies:
      - type: Percent
        value: 50                     # ---> Her seferinde %50 azalt
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0   # ---> Scale up hızlı olsun
      policies:
      - type: Percent
        value: 100                    # ---> Her seferinde 2 katına çıkar
        periodSeconds: 15
```

### VerticalPodAutoscaler (VPA)

```yaml
apiVersion: autoscaling.k8s.io/v1     # ---> VPA API
kind: VerticalPodAutoscaler           # ---> VPA objesi
metadata:
  name: nginx-vpa                     # ---> VPA adı
spec:
  targetRef:                          # ---> Hangi kaynak optimize edilecek
    apiVersion: apps/v1
    kind: Deployment                  # ---> Deployment, StatefulSet, DaemonSet
    name: nginx-deployment
  
  updatePolicy:                       # ---> Güncelleme modu
    updateMode: Auto                  # ---> Auto (otomatik uygula), Recreate, Initial, Off
  
  resourcePolicy:                     # ---> Kaynak sınırları
    containerPolicies:
    - containerName: nginx
      minAllowed:                     # ---> Minimum değerler
        cpu: "100m"
        memory: "128Mi"
      maxAllowed:                     # ---> Maksimum değerler
        cpu: "2"
        memory: "2Gi"
      controlledResources:            # ---> [OPSİYONEL] Hangi kaynaklar kontrol edilsin
      - cpu
      - memory
```
## 17. Namespace

```yaml
apiVersion: v1
kind: Namespace                       # ---> Namespace objesi
metadata:
  name: production                    # ---> Namespace adı
  labels:                             # ---> [ÖNEMLİ] Pod Security Admission (PSA) Etiketleri
    # Modern Güvenlik (v1.25+) - PodSecurityPolicy yerine geçer
    pod-security.kubernetes.io/enforce: restricted  # ---> [KURAL] Sıkı güvenlik (Root yasak, Volume kısıtlı)
                                                   # ---> baseline: Standart güvenlik
                                                   # ---> privileged: Kısıtlama yok (Riskli)
    pod-security.kubernetes.io/enforce-version: "latest"
    
    # Uyarı Modu (Audit için)
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: "latest"
    
    istio-injection: enabled          # ---> [OPSİYONEL] Service Mesh (Istio) sidecar otomatik enjekte et
```

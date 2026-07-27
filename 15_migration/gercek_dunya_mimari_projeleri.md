# Gerçek Dünya Projeleri ve Üretim Mimarileri

Bu bölümde, teorik ve pratik bilgileri birleştirerek, üretim ortamlarında (Production) canlıda çalışan iki farklı uçtan uca mimariyi kurgulayacağız: **Full-Stack E-Ticaret Platformu Mimarisi** ve **Kurumsal GitOps Depo Yapısı**.

---

## Proje 1: Full-Stack E-Ticaret Platformu Mimarisi

Bu projede bir E-Ticaret uygulamasının gereksinim duyduğu tüm katmanlar (Frontend, HPA destekli Backend API, PostgreSQL StatefulSet Veritabanı, Redis In-Memory Cache, Ingress ve TLS) tek bir mimaride birleştirilmiştir.

```text
                                [ İNTERNET TRAFİĞİ ]
                                         |
                                         v (HTTPS: Port 443)
                           [ Nginx Ingress Controller ]
                           (cert-manager SSL Sertifikası)
                                         |
             +---------------------------+---------------------------+
             | Domain: store.mycompany.com                           | Path: /api/*
             v                                                       v
   [ Frontend Deployment ]                               [ Backend API Deployment ]
   (3 Replicas - React/Next.js)                          (Autoscaled HPA: 3-15 Replicas)
                                                                     |
                                           +-------------------------+-------------------------+
                                           |                                                   |
                                           v                                                   v
                               [ PostgreSQL StatefulSet ]                          [ Redis StatefulSet ]
                               (Primary DB + 50GB EBS PVC)                         (Session & Cart Cache)
```

### Komple Uçtan Uca Production Manifesti (`ecommerce-production.yaml`)

> 📄 **Not:** Bu dosya üretim standartlarına (Production-Grade) uygun olarak Namespace, Secret, StatefulSet, Headless Service, Deployment, HPA ve Ingress TLS tanımlamalarını tek bir yerde toplar.

```yaml
# 1. NAMESPACE TANIMI
apiVersion: v1
kind: Namespace
metadata:
  name: ecommerce-prod
---
# 2. HASSAS VERİLER (SECRET)
apiVersion: v1
kind: Secret
metadata:
  name: ecommerce-prod-secrets
  namespace: ecommerce-prod
type: Opaque
stringData:
  POSTGRES_USER: "db_admin_user"
  POSTGRES_PASSWORD: "ProductionSecureDbPassword2026!"
  REDIS_PASSWORD: "ProductionSecureRedisPassword2026!"
---
# 3. VERİTABANI (POSTGRESQL STATEFULSET)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: ecommerce-prod
spec:
  serviceName: postgres-headless-service
  replicas: 1
  selector:
    matchLabels:
      app: postgres-db
  template:
    metadata:
      labels:
        app: postgres-db
    spec:
      containers:
      - name: postgresql
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: ecommerce-prod-secrets
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ecommerce-prod-secrets
              key: POSTGRES_PASSWORD
        volumeMounts:
        - name: postgres-persistent-storage
          mountPath: /var/lib/postgresql/data
  # Dinamik Disk Sağlama
  volumeClaimTemplates:
  - metadata:
      name: postgres-persistent-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: fast-ebs-gp3
      resources:
        requests:
          storage: 50Gi
---
# 4. VERİTABANI SERVİSİ (CLUSTERIP)
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: ecommerce-prod
spec:
  type: ClusterIP
  selector:
    app: postgres-db
  ports:
  - port: 5432
    targetPort: 5432
---
# 5. BACKEND API DEPLOYMENT (HPA UYUMLU)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api-deployment
  namespace: ecommerce-prod
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: backend-api
  template:
    metadata:
      labels:
        app: backend-api
    spec:
      containers:
      - name: api-container
        image: my-registry/ecommerce-api:v2.4.0
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: "postgres-service"
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: ecommerce-prod-secrets
              key: POSTGRES_PASSWORD
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
---
# 6. BACKEND API HPA (OTOMATİK YATAY ÖLÇEKLEME)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-api-hpa
  namespace: ecommerce-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend-api-deployment
  minReplicas: 3
  maxReplicas: 15
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 75
---
# 7. INGRESS & TLS SERTİFİKASI
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ecommerce-main-ingress
  namespace: ecommerce-prod
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-production"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - store.mycompany.com
    secretName: ecommerce-store-tls
  rules:
  - host: store.mycompany.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-api-service
            port:
              number: 8080
```

---

## Proje 2: Kurumsal GitOps Depo Yapısı (Kustomize + ArgoCD)

Büyük ölçekli kurumlarda tüm ortamlar (Dev, Staging, Prod) tek bir klasörde karıştırılmaz. GitOps standartlarına uygun kurumsal klasör mimarisi şu şekilde kurgulanmalıdır:

```text
gitops-enterprise-repo/
├── apps/
│   ├── order-service/
│   │   ├── base/                     <-- Tüm ortamlar için ortak YAML'lar
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── kustomization.yaml
│   │   └── overlays/
│   │       ├── development/          <-- Dev Ortamı (Replica: 1, Debug Logs)
│   │       │   ├── kustomization.yaml
│   │       │   └── patch-env.yaml
│   │       └── production/           <-- Prod Ortamı (Replica: 10, HPA, TLS)
│   │           ├── kustomization.yaml
│   │           └── patch-resources.yaml
│   └── payment-service/
│       ├── base/
│       └── overlays/
└── argocd-infrastructure/
    ├── dev-applicationset.yaml       <-- Dev ortamını otomatik bağlayan ArgoCD kuralı
    └── prod-applicationset.yaml      <-- Prod ortamını otomatik bağlayan ArgoCD kuralı
```

Bu modüler yapı sayesinde bir yazılımcı sadece `overlays/development` klasöründe değişiklik yaparken, üretim ortamı (`overlays/production`) güvende kalır ve tüm süreç Git PR (Pull Request) onay mekanizmasıyla yürütülür.

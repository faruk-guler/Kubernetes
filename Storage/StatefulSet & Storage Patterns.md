# StatefulSet & Storage Patterns

StatefulSet, pod'ların kimliğini (isim, ağ, disk) sabit tutan iş yükü türüdür. Veritabanları, mesaj kuyrukları ve dağıtık sistemler için tasarlanmıştır.

---

## StatefulSet vs Deployment

| Özellik | Deployment | StatefulSet |
|:--------|:-----------|:------------|
| Pod ismi | Rastgele (`web-7f8b4d-xkjl9`) | Sıralı (`mysql-0`, `mysql-1`) |
| Başlatma sırası | Paralel | Sıralı (0 → 1 → 2) |
| Durdurma sırası | Paralel | Ters sıra (2 → 1 → 0) |
| Storage | Paylaşımlı PVC veya geçici | Her pod'a özel PVC (volumeClaimTemplates) |
| DNS | Service IP | Stabil hostname: `mysql-0.mysql.default.svc.cluster.local` |
| Kullanım | Stateless uygulamalar | Veritabanı, Zookeeper, Kafka, Redis Cluster |

---

## volumeClaimTemplates

StatefulSet'in en kritik özelliği: her pod için otomatik PVC oluşturur ve pod silinip yeniden oluşturulduğunda **aynı PVC'ye bağlanır**.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: production
spec:
  serviceName: mysql-headless    # Headless Service zorunlu
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
  volumeClaimTemplates:                 # Her pod için ayrı PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: longhorn
      resources:
        requests:
          storage: 20Gi
```

Bu StatefulSet 3 PVC oluşturur:
- `data-mysql-0` → `mysql-0` pod'una özel
- `data-mysql-1` → `mysql-1` pod'una özel
- `data-mysql-2` → `mysql-2` pod'una özel

---

## Headless Service

StatefulSet pod'larının stabil DNS kayıtları alması için Headless Service gereklidir.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  namespace: production
spec:
  clusterIP: None      # Headless: IP yok, her pod ayrı DNS kaydı alır
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
```

DNS kayıtları:
```
mysql-0.mysql-headless.production.svc.cluster.local → mysql-0 pod IP
mysql-1.mysql-headless.production.svc.cluster.local → mysql-1 pod IP
mysql-2.mysql-headless.production.svc.cluster.local → mysql-2 pod IP
```

---

## MySQL Primary/Replica Deseni

```yaml
# Primary'ı bul (mysql-0 her zaman primary)
# Replica'lar primary'ı DNS üzerinden bulur

# ConfigMap ile primary/replica ayrımı
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-config
data:
  primary.cnf: |
    [mysqld]
    log-bin=mysql-bin
    server-id=1
  replica.cnf: |
    [mysqld]
    super-read-only=1
    server-id=2
```

```yaml
# Init container ile primary/replica rolü belirle
initContainers:
- name: init-mysql
  image: mysql:8.0
  command:
  - bash
  - -c
  - |
    # Pod sırası 0 ise primary, değilse replica
    [[ $(hostname) =~ -([0-9]+)$ ]] || exit 1
    ordinal=${BASH_REMATCH[1]}
    if [[ $ordinal -eq 0 ]]; then
      cp /mnt/config-map/primary.cnf /etc/mysql/conf.d/
    else
      cp /mnt/config-map/replica.cnf /etc/mysql/conf.d/
    fi
```

---

## Kafka StatefulSet Deseni

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
spec:
  serviceName: kafka-headless
  replicas: 3
  template:
    spec:
      containers:
      - name: kafka
        image: confluentinc/cp-kafka:7.5.0
        env:
        - name: KAFKA_BROKER_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['kafka-broker-id']
        - name: KAFKA_ZOOKEEPER_CONNECT
          value: "zookeeper-0.zookeeper:2181,zookeeper-1.zookeeper:2181"
        - name: KAFKA_ADVERTISED_LISTENERS
          value: "PLAINTEXT://$(MY_POD_NAME).kafka-headless:9092"
        volumeMounts:
        - name: data
          mountPath: /var/lib/kafka/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      storageClassName: longhorn
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

---

## StatefulSet Güncelleme Stratejileri

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 2    # Sadece 2 ve üzeri index'li pod'ları güncelle
                      # Canary güncelleme için: önce 1 pod, sorun yoksa tümü
```

```bash
# Canary güncelleme akışı
# 1. partition=2 ile başla (sadece mysql-2 güncellenir)
kubectl patch statefulset mysql -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'

# 2. mysql-2 kontrol et
kubectl exec mysql-2 -- mysql --version

# 3. Başarılıysa partition=0 (tümü güncellenir)
kubectl patch statefulset mysql -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

---

## StatefulSet Yönetimi

```bash
# Pod sıralaması ile scale
kubectl scale statefulset mysql --replicas=5
# mysql-3 ve mysql-4 sırayla oluşturulur, PVC'leri otomatik oluşur

# Scale down (PVC korunur!)
kubectl scale statefulset mysql --replicas=1
# mysql-1, mysql-2 silinir ama PVC'leri KALIR

# PVC'leri de silmek için
kubectl delete pvc data-mysql-1 data-mysql-2

# StatefulSet silinirse PVC'ler yine KALIR (güvenlik)
kubectl delete statefulset mysql
kubectl get pvc | grep mysql   # Hâlâ var
```

---

## PodDisruptionBudget (PDB)

```yaml
# Maintenance veya node failure sırasında minimum kullanılabilirliği garantile
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mysql-pdb
spec:
  minAvailable: 2       # En az 2 pod her zaman ayakta
  # maxUnavailable: 1   # Alternatif: en fazla 1 pod aynı anda down
  selector:
    matchLabels:
      app: mysql
```

```bash
# PDB ile drain
kubectl drain <node> --ignore-daemonsets
# PDB ihlal edilecekse drain durur ve uyarı verir
```

---

## Operasyonel İpuçları

```bash
# StatefulSet pod'larını tek tek yeniden başlat
kubectl rollout restart statefulset mysql

# Belirli pod'u sil (yeniden oluşur, aynı PVC bağlanır)
kubectl delete pod mysql-1
# mysql-1 silinir → aynı isimle yeniden oluşur → data-mysql-1 PVC bağlanır

# StatefulSet durum özeti
kubectl rollout status statefulset mysql

# Tüm pod'ların hazır olup olmadığı
kubectl get statefulset mysql
# READY: 3/3 olmalı
```

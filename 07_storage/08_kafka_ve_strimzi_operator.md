# Kubernetes Üzerinde Apache Kafka: Strimzi Operatörü ve KRaft Mimarisi

Modern mikroservis ekosistemlerinde servisler arası gevşek bağlı (loosely-coupled), asenkron ve yüksek hacimli veri akışı için endüstri standardı **Apache Kafka**'dır. 

Geçmişte Kafka gibi stateful (durum bilgisi tutan) ve disk I/O bağımlı devasa sistemleri Kubernetes üzerinde çalıştırmak riskli görülürdü. Ancak bulut-yerel depolama çözümlerinin gelişmesi ve CNCF kuluçka projesi olan **Strimzi** operatörünün olgunlaşmasıyla birlikte, günümüzde binlerce kurum Kafka kümelerini doğrudan Kubernetes üzerinde yönetmektedir.

---

## 1. ZooKeeper'dan KRaft'a: Modern Kafka Mimarisi

Eski mimaride Kafka, küme koordinasyonu ve metadata yönetimi için ayrı bir **Apache ZooKeeper** kümesine ihtiyaç duyuyordu. Bu durum, iki ayrı dağıtık sistemin (hem Kafka hem ZooKeeper) bakımını ve depolamasını yönetmek anlamına geliyordu.

Modern Kafka sürümleri (v3.5+ ve özellikle v3.7+), **KRaft (Kafka Raft Metadata Mode)** mimarisine geçmiştir.
- **ZooKeeper Bağımlılığı Bitti:** Ekstra ZooKeeper pod'ları ve diskleri çalıştırmanıza gerek kalmaz.
- **Raft Konsensüsü:** Kafka broker'larının bir kısmı (veya tümü) "Controller" rolünü üstlenerek metadatayı doğrudan dahili bir Raft günlüğünde (metadata log) yönetir.
- **Daha Hızlı Kurtarma (Failover):** Milyonlarca partition içeren kümelerde broker yeniden başlatma süreleri dakikalardan saniyelere inmiştir.

---

## 2. Strimzi Operator Mimarisi

**Strimzi**, Apache Kafka'yı Kubernetes üzerinde bildirimsel (declarative) olarak kurmanızı ve işletmenizi sağlayan resmi CNCF operatörüdür. Üç temel operatörden oluşur:

1. **Cluster Operator:** Kafka broker'larını, KRaft controller düğümlerini, Kafka Connect ve MirrorMaker bileşenlerini yönetir.
2. **Topic Operator:** GitOps prensiplerine uygun olarak, `KafkaTopic` CRD nesnesi oluşturduğunuzda Kafka içinde otomatik olarak topic açar, partition sayısını artırır veya konfigürasyonu eşitler.
3. **User Operator:** `KafkaUser` CRD nesnesi ile mTLS sertifikaları veya SCRAM-SHA-512 parolaları oluşturup Kubernetes `Secret` nesnesine kaydeder; ACL (erişim yetkileri) tanımlar.

```
       ┌─────────────────────────────────────────────────────────┐
       │                Strimzi Cluster Operator                 │
       └──────┬──────────────────────┬────────────────────┬──────┘
              │                      │                    │
              ▼                      ▼                    ▼
     ┌─────────────────┐    ┌─────────────────┐  ┌─────────────────┐
     │ Kafka NodePool  │    │  Topic Operator │  │  User Operator  │
     │ (Controllers)   │    │  (KafkaTopic)   │  │  (KafkaUser)    │
     └────────┬────────┘    └─────────────────┘  └─────────────────┘
              │
              ▼
     ┌─────────────────┐
     │ Kafka NodePool  │
     │ (Brokers - PVC) │
     └─────────────────┘
```

---

## 3. Strimzi Kurulumu

Strimzi Operatörünü Helm veya doğrudan resmi manifestolarla kurabilirsiniz:

```bash
# Helm deposunu ekle
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# Strimzi Operatörünü kur
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace
```

Operatör podunun `Running` durumuna geçtiğini doğrulayın:
```bash
kubectl get pods -n kafka -l name=strimzi-cluster-operator
```

---

## 4. KRaft Modunda Kafka Kümesi Tanımlama (`Kafka` & `KafkaNodePool`)

Strimzi'nin modern sürümlerinde her şey **KafkaNodePool** nesneleriyle yönetilir. Bu sayede broker ve controller rollerini fiziksel olarak farklı Kubernetes düğümlerine (farklı StorageClass veya toleration ile) dağıtabilirsiniz.

Aşağıda 3 adet Dual-Role (hem Broker hem Controller) çalışan, persistent SSD depolamaya sahip minimal ve sağlam bir KRaft kümesi tanımı yer almaktadır:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role-pool
  namespace: kafka
  labels:
    strimzi.io/cluster: production-kafka
spec:
  replicas: 3
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 100Gi
        class: fast-ebs-sc # Hızlı NVMe veya SSD StorageClass
        deleteClaim: false # Küme silinse bile PVC'ler kazaen silinmesin!
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: production-kafka
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.7.0
    metadataVersion: 3.7-IV4
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

Bu manifest uygulandığında Strimzi otomatik olarak 3 adet StatefulSet pod'u (`production-kafka-dual-role-pool-0`, `1`, `2`) ve ilgili PVC disklerini ayağa kaldıracaktır.

---

## 5. GitOps ile Topic ve Kullanıcı Yönetimi

Kafka üzerinde bir topic veya kullanıcı açmak için artık Kafka poduna `bash` ile girip `kafka-topics.sh` çalıştırmanıza gerek yoktur!

### Otomatik Topic Oluşturma (`KafkaTopic`)
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: order-events-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: production-kafka
spec:
  partitions: 6
  replicas: 3
  config:
    retention.ms: 604800000 # 7 gün saklama
    segment.bytes: 1073741824 # 1 GB segment boyutu
```

### Güvenli Kullanıcı Oluşturma (`KafkaUser`)
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: payment-service-user
  namespace: kafka
  labels:
    strimzi.io/cluster: production-kafka
spec:
  authentication:
    type: tls # mTLS sertifikası üretir
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: order-events-topic
          patternType: literal
        operation: Read
```
Strimzi User Operator bu YAML'ı gördüğü anda `payment-service-user` adında bir Kubernetes `Secret`'ı oluşturur ve içine istemcinin kullanacağı `ca.crt`, `user.crt` ve `user.key` sertifikalarını koyar.

---

## 6. SRE ve Üretim Ortamı En İyi Pratikleri

1. **`deleteClaim: false` Güvencesi:** Depolama tanımında `deleteClaim: false` kullanarak yanlışlıkla `kubectl delete kafka` yapılsa dahi Kafka verilerinin bulunduğu PVC disklerinin silinmesini engelleyin.
2. **PodDisruptionBudget (PDB):** Strimzi otomatik olarak PDB oluşturur. Düğüm güncellemelerinde (`kubectl drain`), ISR (In-Sync Replicas) sayısı minimumun altına düşmeyecek şekilde podlar teker teker tahliye edilir.
3. **Pod Anti-Affinity:** Kafka broker podlarının asla aynı fiziksel düğüme (node) veya aynı availability zone'a denk gelmemesi için `topologySpreadConstraints` veya anti-affinity kuralları zorunlu tutulmalıdır.
4. **JVM ve Bellek Yönetimi:** Kafka, disk I/O için işletim sistemi PageCache mekanizmasını yoğun şekilde kullanır. Bu nedenle pod belleğinin tamamını JVM Heap'e (`-Xmx`) vermeyin; toplam RAM'in en fazla %50'sini heap yapın, kalan %50'yi Linux PageCache için serbest bırakın.

## Özet
Strimzi ve KRaft birleşimi, Kubernetes üzerinde durum bilgisi tutan (stateful) büyük veri sistemlerinin nasıl başarıyla yönetileceğinin en mükemmel örneğidir. GitOps ile entegre edilen `KafkaTopic` ve `KafkaUser` nesneleri, geliştirici ekiplerinin operasyonel yükünü sıfıra indirir.

# DaemonSet

Kubernetes'te `Deployment` veya `StatefulSet` kullandığımızda cluster'a "Bu uygulamadan 3 adet kopya çalıştır" deriz. Kubernetes'in akıllı zamanlayıcısı (Scheduler) bu pod'ları en uygun gördüğü node'lar üzerine dağıtır. Hatta bazen iki pod aynı node'da çalışırken, bir diğer node tamamen boş kalabilir. Ancak bazı durumlar vardır ki pod'ların cluster geneline dağılması yetmez; **her bir worker node üzerinde tam olarak bir adet pod'un çalışıyor olması gerekir.**

İşte bu ihtiyacı karşılamak için Kubernetes bizlere **DaemonSet** objesini sunmaktadır.

---

## Neden DaemonSet?

Bunu daha iyi anlamak için gerçek bir sistem yönetimi senaryosunu ele alalım:

* **Senaryo:** Cluster'ımızda 5 adet worker node bulunuyor ve biz bu node'ların donanım sıcaklıklarını, işlemci ve bellek metriklerini toplamak istiyoruz (node-exporter). Veya her node üzerindeki container loglarını (fluentbit/promtail) toplayıp merkezi bir log sunucusuna göndermemiz gerekiyor.
* **Deployment Denemesi:** Eğer bu iş için 5 replikalı bir `Deployment` oluşturursak, Scheduler bu pod'larır 3 farklı node üzerine yığabilir ve diğer 2 node metrik toplanamadığı için kör kalır.
* **Ölçekleme Sıkıntısı:** Ayrıca yarın bir gün cluster'ımıza 2 yeni node daha eklediğimizde Deployment'ı elle 7 replikaya scale etmemiz gerekir. Node'lardan biri silindiğinde ise bu sefer replika sayısı fazla gelir.

**DaemonSet Çözümü:** Bu görevi bir `DaemonSet` olarak deploy ettiğimizde Kubernetes şunları garanti eder:
* Cluster'daki her bir sağlıklı node üzerinde otomatik olarak **bir adet** pod ayağa kaldırılır.
* Cluster'a yeni bir node eklendiğinde, Scheduler araya girmeden yeni node üzerinde otomatik olarak DaemonSet pod'u başlatılır.
* Bir node cluster'dan çıkarıldığında (veya silindiğinde), o node üzerinde çalışan pod da silinir ve arkasında çöp bırakmaz.

---

## Temel DaemonSet Anatomisi

Aşağıda, cluster genelindeki sistem loglarını toplamak amacıyla yazılmış örnek bir Fluentbit DaemonSet manifestosu bulunmaktadır:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
  namespace: monitoring
  labels:
    app: log-collector
spec:
  selector:
    matchLabels:
      app: log-collector
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      # DaemonSet'in master/control-plane node'larında da çalışabilmesi için tolerations tanımları
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoExecute
      - key: node.kubernetes.io/unreachable
        operator: Exists
        effect: NoExecute

      serviceAccountName: log-collector-sa
      containers:
      - name: fluentbit
        image: fluent/fluent-bit:2.2.2
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: config
          mountPath: /fluent-bit/etc/
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: config
        configMap:
          name: fluentbit-config
      priorityClassName: system-node-critical
```

### Kritik Alanların Açıklamaları

* **Tolerations:** Master veya Control Plane gibi sistem yönetici node'ları varsayılan olarak normal pod'ların üzerinde çalışmasını engellemek için taints (engeller) barındırır. Fluentbit gibi kritik altyapı pod'larının her node'da çalışebilmesi için bu taints engellerini aşacak `tolerations` tanımlarının yapılması şarttır.
* **hostPath:** Log toplayıcıların fiziksel olarak o node üzerindeki log dosyalarına (örneğin `/var/log`) erişebilmesi gerekir. Bu amaçla host node üzerindeki dizini container içine mount etmek için `hostPath` volume türü kullanılır.
* **priorityClassName:** `system-node-critical` değeri, node üzerinde kaynak (RAM/CPU) sıkışıklığı yaşandığında bu pod'un diğer kullanıcı pod'ları gibi sistemden atılmasını (eviction) engeller.

---

## Seçici Node Hedefleme (Node Selection)

Her zaman tüm node'larda değil, sadece belirli niteliklere sahip node'larda DaemonSet çalıştırmak isteyebiliriz. Örneğin; sadece GPU barındıran node'larda bir donanım izleme aracı çalıştırmak istiyorsak `nodeSelector` veya `nodeAffinity` kullanabiliriz.

```yaml
spec:
  template:
    spec:
      # Sadece GPU node'larını hedefleme
      nodeSelector:
        node-role: gpu-worker
```

Veya daha esnek kurallar için `nodeAffinity` kullanılabilir:

```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node.kubernetes.io/instance-type
                operator: In
                values: ["g4dn.xlarge", "g4dn.2xlarge"]
```

---

## Güncelleme Stratejileri (Update Strategies)

DaemonSet güncellemeleri cluster genelini etkilediği için dikkatle yönetilmelidir:

* **RollingUpdate (Varsayılan):** Güncelleme sırasında eski pod'lar sırayla silinir ve yenileri kurulur. `maxUnavailable: 1` parametresi aynı anda en fazla 1 node'un log/metrik servisinin kesintiye uğramasını garanti eder.
* **OnDelete:** DaemonSet şablonunu güncellediğinizde hiçbir şey olmaz. Ancak siz bir node üzerindeki DaemonSet pod'unu manuel olarak sildiğinizde, Kubernetes o node üzerinde yeni versiyona sahip pod'u başlatır. Bu strateji kritik production güncellemelerinde kontrolün tamamen sizde olmasını sağlar.

---

## Gerçek Dünya Örnekleri

### 1. Fluentbit Log Pipeline Yapılandırması

Fluentbit'in node'lardan logları toplayıp merkezi bir Loki log sunucusuna göndermesini sağlayan ConfigMap yapılandırması:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentbit-config
  namespace: monitoring
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Log_Level     info
        Parsers_File  parsers.conf

    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*.log
        Parser            docker
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     50MB
        Skip_Long_Lines   On
        Refresh_Interval  10

    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_Log           On
        K8S-Logging.Parser  On
        K8S-Logging.Exclude On

    [FILTER]
        Name  grep
        Match kube.*
        Exclude log .*healthcheck.*

    [OUTPUT]
        Name            loki
        Match           kube.*
        Host            loki.monitoring.svc.cluster.local
        Port            3100
        Labels          job=fluentbit,node=${NODE_NAME}
        Label_Keys      $kubernetes['namespace_name'],$kubernetes['pod_name'],$kubernetes['container_name']
        Batch_wait      1
        Batch_size      1001024

  parsers.conf: |
    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
```

### 2. Node-Exporter DaemonSet (Prometheus Metrikleri)

Her node'un CPU, bellek ve disk kullanımını ana host seviyesinde toplamak için tasarlanmış `node-exporter` pod tanımı:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.7.0
        args:
        - --path.rootfs=/host
        - --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|snap)($|/)
        ports:
        - containerPort: 9100
          hostPort: 9100
        volumeMounts:
        - name: root
          mountPath: /host
          readOnly: true
        securityContext:
          readOnlyRootFilesystem: true
          runAsUser: 65534
      volumes:
      - name: root
        hostPath:
          path: /
      tolerations:
      - operator: Exists
```

---

## Yönetim ve İzleme Komutları

```bash
# DaemonSet durumunu sorgulama
kubectl get daemonset -n monitoring

# DaemonSet altındaki pod'ların hangi node'larda çalıştığını görme
kubectl get pods -n monitoring -l app=log-collector -o wide

# Güncelleme sürecini takip etme
kubectl rollout status daemonset/log-collector -n monitoring

# Güncellemeyi geri alma (Rollback)
kubectl rollout undo daemonset/log-collector -n monitoring
```

### Prometheus İzleme Alarmları

```promql
# Cluster'da kaç node'da DaemonSet pod'unun eksik çalıştığını tespit etme
kube_daemonset_status_desired_number_scheduled{daemonset="log-collector"} - 
kube_daemonset_status_number_ready{daemonset="log-collector"} > 0
```

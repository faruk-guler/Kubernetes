# DaemonSet

DaemonSet, her node'da (veya seçilmiş node'larda) tam olarak bir pod çalıştırmayı garanti eder. Yeni node eklendiğinde pod otomatik başlatılır, node kaldırıldığında pod temizlenir.

---

## DaemonSet Ne Zaman Kullanılır?

```
Deployment:  "Cluster'da toplam 3 kopya çalışsın" → Scheduler karar verir
DaemonSet:   "Her node'da 1 kopya çalışsın" → Node başına 1 pod garantisi

Kullanım alanları:
  ✅ Log toplayıcılar (Fluentbit, Promtail, Filebeat)
  ✅ Metrik toplayıcılar (node-exporter)
  ✅ CNI plugin'ler (Cilium, Calico agent)
  ✅ Storage plugin'ler (Longhorn manager, Rook)
  ✅ Güvenlik agent'ları (Falco, Wazuh)
  ✅ Network proxy'ler (kube-proxy)
  ✅ GPU sürücüleri (NVIDIA device plugin)
```

---

## Temel DaemonSet

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

  # Güncelleme stratejisi
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1     # Aynı anda en fazla 1 node'da güncelle

  template:
    metadata:
      labels:
        app: log-collector
    spec:
      # DaemonSet için tolerations — sistem node'larına da girebilsin
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

      # Sistem namespace'lerindeki log'lara erişim için
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
              fieldPath: spec.nodeName    # Hangi node'da olduğunu bilsin
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

      # DaemonSet pod'larını sistem pod'larıyla aynı önceliğe al
      priorityClassName: system-node-critical
```

---

## Seçici Node Hedefleme

```yaml
# Yalnızca belirli node'larda çalıştır
spec:
  template:
    spec:
      # NodeSelector ile
      nodeSelector:
        kubernetes.io/os: linux
        node-role: gpu-worker

      # veya NodeAffinity ile (daha esnek)
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node.kubernetes.io/instance-type
                operator: In
                values: ["g4dn.xlarge", "g4dn.2xlarge"]   # Sadece GPU node'lar
```

---

## Gerçek Dünya: Fluentbit Log Pipeline

```yaml
# fluentbit-config ConfigMap
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
        K8S-Logging.Exclude On    # fluentbit.io/exclude: "true" annotation'lı pod'ları atla

    [FILTER]
        Name  grep
        Match kube.*
        Exclude log .*healthcheck.*   # Healthcheck log'larını at

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

    [PARSER]
        Name        nginx
        Format      regex
        Regex       ^(?<remote>[^ ]*) .* \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*) "(?<referer>[^\"]*)" "(?<agent>[^\"]*)"
        Time_Key    time
        Time_Format %d/%b/%Y:%H:%M:%S %z
```

---

## Node-Exporter DaemonSet (Prometheus)

```yaml
# node-exporter — her node'un CPU/RAM/Disk metriklerini toplar
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
      hostNetwork: true       # Host network namespace — gerçek metrikler
      hostPID: true           # Host PID namespace
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
      - operator: Exists       # Tüm taint'lere tolerans — her node'da çalış
```

---

## Güncelleme Stratejileri

```yaml
# RollingUpdate (varsayılan) — önerilen
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1         # Aynı anda en fazla 1 pod offline

# OnDelete — manuel kontrol
updateStrategy:
  type: OnDelete
  # Güncelleme için pod'u elle silmen gerekir
  # kubectl delete pod <pod-name>
  # DaemonSet yeni versiyonla yeniden başlatır
```

---

## Pod'a Özgün Davranış Verme

```yaml
# Her pod kendi node adını biliyor — node bazlı config için kullanışlı
env:
- name: NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName

- name: NODE_IP
  valueFrom:
    fieldRef:
      fieldPath: status.hostIP

- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

---

## İzleme ve Yönetim

```bash
# DaemonSet durumu
kubectl get daemonset -n monitoring
# NAME            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
# log-collector   5         5         5       5            5           <none>

# Hangi node'larda çalışıyor?
kubectl get pods -n monitoring -l app=log-collector -o wide

# DESIRED != READY → Sorun var
kubectl describe daemonset log-collector -n monitoring

# Güncelleme durumu
kubectl rollout status daemonset/log-collector -n monitoring

# Rollback
kubectl rollout undo daemonset/log-collector -n monitoring
```

```promql
# Prometheus: DaemonSet sağlık kontrolü
# Tüm node'larda çalışıyor mu?
kube_daemonset_status_desired_number_scheduled{daemonset="log-collector"} -
kube_daemonset_status_number_ready{daemonset="log-collector"} > 0
```

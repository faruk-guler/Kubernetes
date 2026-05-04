# Grafana Dashboards

Grafana, metrik ve log verilerini görselleştiren açık kaynak platformdur. 2026'da Kubernetes izlemesinin standart arayüzüdür — sadece görsel değil, alerting ve on-call yönetimi için de kullanılır.

---

## Erişim ve Temel Kurulum

```bash
# Grafana UI'a eriş (kube-prometheus-stack ile kuruluysa)
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Admin şifresi
kubectl get secret prometheus-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Hazır Dashboard'lar (Import)

Grafana.com'daki hazır dashboard'ları ID ile import edin:

```bash
# Grafana UI → Dashboards → Import → ID gir
```

| Dashboard ID | İsim | Açıklama |
|:---:|:------|:---------|
| **15757** | Kubernetes Cluster Overview | Node/Pod/Container genel bakış |
| **15172** | Node Exporter Full | CPU, RAM, Disk, Network detay |
| **13659** | Loki Log Dashboard | Log arama ve görselleştirme |
| **16611** | Cilium/Hubble | eBPF ağ akışları |
| **12740** | Kubernetes Persistent Volumes | PV/PVC kullanımı |
| **19105** | K8s Namespace Overview | Namespace bazında kaynak |
| **7249** | Kubernetes Cluster | Genel sağlık özeti |
| **11074** | Node Exporter Quickstart | Hızlı node durumu |

---

## Dashboard as Code (Grafana Operator)

Dashboard'ları YAML ile yönetin — GitOps uyumlu:

```bash
# Grafana Operator kurulumu
helm install grafana-operator \
  oci://ghcr.io/grafana/helm-charts/grafana-operator \
  --namespace monitoring
```

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: kubernetes-overview
  namespace: monitoring
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  json: |
    {
      "title": "Kubernetes Overview",
      "uid": "k8s-overview-2026",
      "panels": [
        {
          "title": "Pod CPU Kullanımı",
          "type": "timeseries",
          "targets": [{
            "expr": "sum(rate(container_cpu_usage_seconds_total{container!=''}[5m])) by (pod)",
            "legendFormat": "{{pod}}"
          }]
        }
      ],
      "time": {"from": "now-1h", "to": "now"},
      "refresh": "30s"
    }
```

---

## Grafana Provisioning (Helm Values ile)

```yaml
# values.yaml
grafana:
  adminPassword: "SecurePass2026!"
  
  # Otomatik datasource
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-kube-prometheus-prometheus:9090
        isDefault: true
        editable: false
      - name: Loki
        type: loki
        url: http://loki:3100
      - name: Tempo
        type: tempo
        url: http://tempo:3100

  # Otomatik dashboard klasörü
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: 'Kubernetes'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

  # Grafana.com'dan dashboard çek
  dashboards:
    default:
      kubernetes-overview:
        gnetId: 15757
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 15172
        revision: 1
        datasource: Prometheus
```

---

## Alerting (Grafana Unified Alerting)

```yaml
# Grafana Alert Rule (UI veya YAML)
# UI: Alerting → Alert Rules → New Alert Rule

# Örnek: Pod CrashLoop alarmı
Condition: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 3
For: 5m
Labels:
  severity: critical
  team: platform
Annotations:
  summary: "Pod CrashLoop: {{ $labels.pod }}"
  runbook: "https://wiki.company.com/runbooks/crashloop"
```

### Notification Channel (Contact Points)

```yaml
# Slack entegrasyonu
apiVersion: 1
contactPoints:
- orgId: 1
  name: slack-platform
  receivers:
  - uid: slack-uid
    type: slack
    settings:
      url: https://hooks.slack.com/services/xxx/yyy/zzz
      channel: "#alerts-platform"
      title: "{{ .CommonLabels.alertname }}"
      text: "{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}"
    disableResolveMessage: false

# PagerDuty
- orgId: 1
  name: pagerduty-oncall
  receivers:
  - uid: pd-uid
    type: pagerduty
    settings:
      integrationKey: "your-pd-integration-key"
      severity: "{{ .CommonLabels.severity }}"
```

---

## Loki ile Log Korelasyonu

Grafana'da metrik + log'ları yan yana görün:

```logql
# Loki sorgu örnekleri (Grafana Explore)

# Belirli namespace'teki ERROR logları
{namespace="production"} |= "ERROR"

# JSON parse ile field çıkar
{app="api"} | json | status_code >= 500

# Son 5 dakikada hata sayısı
sum(count_over_time({namespace="production"} |= "ERROR" [5m]))

# İki servis arasındaki log karşılaştırma
{app=~"api|worker"} | json | line_format "{{.level}} {{.message}}"
```

---

## Grafana Yönetimi

```bash
# Grafana'yı yeniden başlat (config değişikliği sonrası)
kubectl rollout restart deployment prometheus-grafana -n monitoring

# Grafana API ile dashboard yedekle
curl -s http://admin:pass@localhost:3000/api/dashboards/home | jq .

# Tüm dashboard'ları listele
curl -s http://admin:pass@localhost:3000/api/search | jq '.[].title'

# Dashboard JSON'unu export et
curl -s http://admin:pass@localhost:3000/api/dashboards/uid/k8s-overview-2026 | \
  jq '.dashboard' > dashboard-backup.json
```

> [!TIP]
> Dashboard'ları Git'te tutun. Grafana Operator veya `grafana-dashboard-sidecar` ile ConfigMap'teki JSON dosyaları otomatik yüklenir.

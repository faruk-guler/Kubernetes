# Prometheus Operator ve Özel Kaynak Tanımları (CRDs)

Geleneksel Prometheus kurulumlarında scrape (metrik toplama) ayarlarını ve kurallarını `prometheus.yml` isimli tek bir büyük konfigürasyon dosyasında yönetmek ve her değişiklikte Prometheus'u yeniden başlatmak 2026 standartlarında bir anti-pattern'dir.

**Prometheus Operator**, Kubernetes üzerinde koşan Prometheus altyapısını tamamen Kubernetes-native **Custom Resource Definitions (CRDs)** nesneleri aracılığıyla yönetir. Yapılandırma değişiklikleri sıfır kesintiyle (zero-downtime) otomatik olarak Prometheus sunucusuna yansıtılır.

---

## 1. Kurulum ve CRD Yapısı

kube-prometheus-stack kurulduğunda Kubernetes API sunucusuna şu temel CRD'ler eklenir:

```bash
# Sektörde en sık kullanılan monitoring CRD'leri:
kubectl get crds | grep monitoring.coreos.com

# Sonuçlar:
# prometheuses.monitoring.coreos.com       -> Prometheus sunucusunu temsil eder
# alertmanagers.monitoring.coreos.com     -> Alertmanager kümesini temsil eder
# servicemonitors.monitoring.coreos.com   -> Servis bazlı metrik toplama
# podmonitors.monitoring.coreos.com       -> Pod bazlı metrik toplama
# prometheusrules.monitoring.coreos.com   -> Uyarı ve metrik ön-işleme kuralları
```

---

## 2. ServiceMonitor — Servis Bazlı Scraping

`ServiceMonitor`, belirli etiketlere (labels) sahip Kubernetes Servislerini (Services) otomatik olarak keşfeder ve bu servislerin arkasında duran pod'lardan metrikleri çeker. En yaygın kullanılan metrik toplama yöntemidir.

### Örnek ServiceMonitor Tanımı

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment-service-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

---

## 3. PodMonitor — Pod Bazlı Scraping

Kubernetes'te bir endpoint'in önünde Service (Servis) nesnesi bulunmuyorsa (örneğin DaemonSet olarak her node'da çalışan ajanlar veya sadece internal çalışan bağımsız podlar), metrikleri doğrudan podlardan toplamak için `PodMonitor` kullanılır.

### Örnek PodMonitor Tanımı

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: redis-cluster-pod-monitor
  namespace: database
spec:
  selector:
    matchLabels:
      app: redis-cluster
  podMetricsEndpoints:
    - port: metrics
      interval: 10s
```

---

## 4. PrometheusRule — Uyarı ve Kayıt Kuralları (Alert & Recording Rules)

Prometheus üzerinde çalışan sorguları önceden işlemek (Recording Rules) veya belirlenen eşik değerleri aşıldığında uyarı üretmek (Alerting Rules) için `PrometheusRule` kullanılır.

### Örnek PrometheusRule Tanımı

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: api-high-error-rate-alerts
  namespace: monitoring
spec:
  groups:
    - name: api-alerts
      rules:
        - alert: HighHttp5xxErrorRate
          expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100 > 5
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "HTTP 5xx Hata Oranı %5 Üzerinde!"
            description: "Servis son 5 dakikadır yüksek oranda 5xx sunucu hatası vermektedir."
```

---

## 5. AlertmanagerConfig — Bildirim Yönlendirme (Routes & Receivers)

Her isim alanının kendi uyarılarını farklı kanallara (örneğin payment ekibinin uyarılarını kendi Slack kanalına, sistem ekibinin uyarılarını e-postaya) yönlendirebilmesi için `AlertmanagerConfig` CRD nesnesi kullanılır:

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: slack-alerts
  namespace: monitoring
spec:
  route:
    groupBy: ['alertname', 'namespace']
    groupWait: 30s
    repeatInterval: 4h
    receiver: 'slack-notifications'
  receivers:
    - name: 'slack-notifications'
      slackConfigs:
        - channel: '#k8s-critical-alerts'
          apiURL:
            name: alertmanager-slack-webhook
            key: url
          sendResolved: true
```

---

## 6. Prometheus Custom Resource (CR) — Yüksek Kullanılabilirlik (HA)

Operatörün çalıştırdığı Prometheus sunucularının yüksek kullanılabilirlikte (HA) ve veri kaybı olmadan çalışması için `Prometheus` CR nesnesi üzerinden replica sayısı ve disk yapılandırmaları yönetilir:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: k8s-prometheus
  namespace: monitoring
spec:
  replicas: 2
  serviceAccountName: prometheus-k8s
  serviceMonitorSelector: {}
  podMonitorSelector: {}
  ruleSelector: {}
  retention: 15d
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: gp3-encrypted
        resources:
          requests:
            storage: 100Gi
```

---

## 7. Doğrulama ve Sorun Giderme (Troubleshooting)

Prometheus Operator ile çalışırken en sık karşılaşılan hata **label (etiket) uyumsuzluğudur**. Yazdığınız bir `ServiceMonitor` metrikleri toplamıyorsa şu adımları izleyin:

```bash
# 1. Sistemdeki aktif ServiceMonitor listesini alın
kubectl get servicemonitors -A

# 2. Prometheus sunucu arayüzüne port-forward ile bağlanın
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Tarayıcıda şu adresleri kontrol edin:
# http://localhost:9090/targets -> Eklediğiniz hedefler listede görünüyor mu ve durumları UP mı?
# http://localhost:9090/rules   -> PrometheusRule ile yazdığınız uyarılar sisteme yüklenmiş mi?

# 3. Kuralın etiketini doğrulayın:
# Prometheus CR nesnesinin hangi etiketleri aradığına bakın (Örn: release: prometheus).
# Eğer ServiceMonitor dosyanızda bu etiket yoksa, Prometheus onu görmezden gelir.
```

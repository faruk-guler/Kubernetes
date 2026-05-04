# SLO & SLA Management

> [!NOTE]
> Bu dosya SLO/SLI kavramları, Pyrra ile uygulama, burn rate alerting ve error budget kültürünü kapsar. Ayrıca bkz: `Prometheus Deep Dive.md` (recording rules detayları) ve `Grafana Dashboards.md` (görselleştirme).

Kubernetes cluster'ınız metrik üretiyor — ama "iyi mi kötü mü?" sorusuna cevap veremiyorsa, gözlemlenebilirlik tamamlanmamış demektir. SLO (Service Level Objective), bu soruyu nicelleştirir.

---

## Temel Kavramlar

| Terim | Tanım | Örnek |
|:------|:------|:------|
| **SLA** | Service Level Agreement — müşteriyle anlaşma | "%99.9 uptime garantisi" |
| **SLO** | Service Level Objective — iç hedef | "%99.95 başarılı istek oranı" |
| **SLI** | Service Level Indicator — ölçülen metrik | "Başarılı istek / toplam istek" |
| **Error Budget** | SLO ihlali için izin verilen süre | "Ayda 21.6 dakika kesinti" |

### Error Budget Hesabı

```
SLO: %99.9 uptime (30 günlük ay için)
Toplam süre: 30 × 24 × 60 = 43,200 dakika
İzin verilen downtime: 43,200 × 0.001 = 43.2 dakika/ay

SLO: %99.99 uptime
İzin verilen downtime: 43,200 × 0.0001 = 4.32 dakika/ay ← çok az!
```

---

## SLI Tasarımı

İyi bir SLI, kullanıcı deneyimini doğrudan ölçer.

### İstek Tabanlı SLI'lar

```promql
# Availability SLI — Başarılı istek oranı
sum(rate(http_requests_total{code!~"5.."}[5m])) /
sum(rate(http_requests_total[5m]))

# Latency SLI — 300ms altındaki isteklerin oranı
sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m])) /
sum(rate(http_request_duration_seconds_count[5m]))

# Saturation SLI — CPU kullanım oranı
1 - (
  sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) /
  sum(kube_pod_container_resource_limits{resource="cpu"})
)
```

### Hata Bütçesi PromQL

```promql
# Kalan hata bütçesi yüzdesi (son 30 gün)
(
  1 - (
    sum(rate(http_requests_total{code=~"5.."}[30d])) /
    sum(rate(http_requests_total[30d]))
  )
) / (1 - 0.999)    # 0.999 = SLO hedefi (%99.9)
```

---

## Pyrra — Kubernetes Native SLO

Pyrra, SLO'ları CRD olarak tanımlar ve Prometheus recording/alerting kurallarını otomatik üretir.

```bash
# Pyrra kurulumu
kubectl apply -f https://raw.githubusercontent.com/pyrra-dev/pyrra/main/config/operator/deploy.yaml
```

```yaml
apiVersion: pyrra.dev/v1alpha1
kind: ServiceLevelObjective
metadata:
  name: api-availability
  namespace: monitoring
spec:
  target: "99.9"             # %99.9 SLO
  window: 4w                 # 4 haftalık pencere

  serviceLevel:
    objectives:
    - ratio:
        errors:
          metric:
            name: http_requests_total
            matchers:
            - name: code
              value: "5.."
              matchType: =~
        total:
          metric:
            name: http_requests_total
        grouping:
        - job
        - namespace
```

Pyrra otomatik üretir:
- **Recording rules**: SLI metrikleri önceden hesaplar
- **Alerting rules**: Error budget tükenmeden uyarır
- **Grafana dashboard**: SLO görselleştirmesi

---

## Multi-Window, Multi-Burn Rate Alerting

Google SRE kitabından: Tek threshold yerine çoklu zaman penceresi ve burn rate kullanın.

```yaml
# Prometheus Alert Rules
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
  - name: slo.api-availability
    rules:

    # CRITICAL: 1 saatte %14.4 burn rate (2 saatte bütçe biter)
    - alert: SLOBudgetBurningFast
      expr: |
        (
          sum(rate(http_requests_total{code=~"5.."}[1h]))
          / sum(rate(http_requests_total[1h]))
        ) > (14.4 * 0.001)    # 14.4x burn rate, SLO %99.9
      for: 2m
      labels:
        severity: critical
        slo: api-availability
      annotations:
        summary: "SLO error budget hızla tükeniyor"
        description: "Son 1 saatte %{{ $value | humanizePercentage }} hata oranı"

    # WARNING: 6 saatte %6x burn rate
    - alert: SLOBudgetBurningSlow
      expr: |
        (
          sum(rate(http_requests_total{code=~"5.."}[6h]))
          / sum(rate(http_requests_total[6h]))
        ) > (6 * 0.001)
      for: 15m
      labels:
        severity: warning
        slo: api-availability
      annotations:
        summary: "SLO error budget yavaş tükeniyor"
```

### Burn Rate Tablosu

| Burn Rate | Bütçe Tükenme Süresi | Pencere | Öncelik |
|:---:|:---:|:---:|:---:|
| 14.4x | 2 saat | 1h + 5m | 🔴 Critical |
| 6x | 5 saat | 6h + 30m | 🟠 Warning |
| 3x | 10 saat | 1d + 6h | 🟡 Info |
| 1x | 30 gün | - | ✅ Normal |

---

## Grafana SLO Dashboard

```yaml
# Grafana panel: Error Budget Kalan
{
  "title": "Error Budget Remaining",
  "type": "gauge",
  "targets": [{
    "expr": "((1 - (sum(rate(http_requests_total{code=~'5..'}[30d])) / sum(rate(http_requests_total[30d])))) / (1 - 0.999)) * 100",
    "legendFormat": "Budget %"
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "thresholds": {
        "steps": [
          {"color": "red",    "value": 0},
          {"color": "yellow", "value": 25},
          {"color": "green",  "value": 50}
        ]
      }
    }
  }
}
```

---

## SLO Kültürü

> [!NOTE]
> **%100 SLO hedeflemeyin.** %100 hedef, değişiklik yapmayı imkansız kılar. Google'ın kendi hedefi kritik servisler için bile %99.99'dur.

**Pratik Öneriler:**

- **SLO'yu müşteriyle birlikte belirleyin** — teknik ekip değil, iş birimi ne kadar tolerans tanıyacağına karar verir
- **Error budget sıfırlandığında → yeni feature yok**, sadece güvenilirlik çalışması yapılır
- **Her SLO için runbook yazın** — alarm geldiğinde kim ne yapacak?
- **Quarterly SLO review** — hedefler gerçekçi mi, güncellemeli miyiz?

```bash
# Son 30 günün SLI özeti
kubectl exec -n monitoring prometheus-0 -- \
  promtool query instant \
  'sum(rate(http_requests_total{code!~"5.."}[30d])) / sum(rate(http_requests_total[30d]))'
```

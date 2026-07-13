# Grafana Arayüzleri ve Görselleştirme (Grafana Dashboards)

**Grafana**, Kubernetes kümenizdeki metrikleri, günlükleri (logs) ve dağıtık izleme (tracing) verilerini görselleştiren, analiz eden ve ekibe alarm üreten açık kaynaklı bir gözlemlenebilirlik platformudur. Modern altyapılarda sadece bir izleme ekranı değil, aynı zamanda **Grafana Unified Alerting** ve On-Call sistemleri ile ekiplerin olay yönetim (incident management) merkezidir.

---

## 1. Erişim ve Giriş Bilgileri

Grafana paneline yerel tarayıcınızdan erişmek ve yetkili admin şifresini çözmek için şu adımlar uygulanır:

```bash
# 1. Grafana servisini yerel 3000 portuna yönlendirin:
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# 2. Kubernetes Secret nesnesinden base64 kodlu admin şifresini çözün:
kubectl get secret prometheus-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 --decode
```

Giriş yapmak için tarayıcınızda `http://localhost:3000` adresine gidin. Kullanıcı adı varsayılan olarak `admin`'dir.

---

## 2. Hazır Dashboard'lar (Import)

Grafana.com topluluğunun ürettiği hazır panelleri saniyeler içinde içe aktarmak (import) için Grafana sol menüsündeki **Dashboards -> Import** yolunu izleyip aşağıdaki ID değerlerini girmeniz yeterlidir:

| Dashboard ID | Panel Adı | Açıklama |
|:---:|:---|:---|
| **15757** | Kubernetes Cluster Overview | Düğümlerin (Nodes), Pod'ların ve Konteynerlerin genel durumları, CPU/RAM kullanımı. |
| **15172** | Node Exporter Full | Fiziksel/sanal sunucuların disk I/O, network trafiği ve işlemci detayları. |
| **13659** | Loki Log Dashboard | Loki loglarını detaylı arama ve metriklerle ilişkilendirme. |
| **16611** | Cilium/Hubble | eBPF tabanlı ağ trafiği, paket kayıpları ve ağ akış şemaları. |
| **12740** | Kubernetes Persistent Volumes | PV / PVC disk doluluk oranları ve okuma/yazma hızları. |
| **19105** | K8s Namespace Overview | İsim alanları (Namespaces) bazında toplam CPU, Bellek ve kaynak limiti tüketimi. |

---

## 3. Kod Olarak Dashboard (Dashboard as Code)

Kullanıcı arayüzünden el ile oluşturulan paneller zamanla kaybolabilir veya takibi zorlaşabilir. **Grafana Operator** sayesinde, panellerinizi birer YAML dosyası (CRD) olarak Git sunucunuzda tutup GitOps (ArgoCD) ile otonom olarak yönetebilirsiniz.

### Grafana Operator Kurulumu

```bash
helm install grafana-operator oci://ghcr.io/grafana/helm-charts/grafana-operator --namespace monitoring
```

### Örnek `GrafanaDashboard` CRD Nesnesi

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [grafana_panelleri_manifest_1.yaml](../Manifests/08_observability/grafana_panelleri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Grafana Provisioning (Helm ile Otomatik Kaynak Tanımlama)

`kube-prometheus-stack` kurarken, veri kaynaklarını (Datasources) ve hazır panelleri `values.yaml` dosyası içinde tanımlayarak kurulum anında hazır gelmelerini sağlayabilirsiniz:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [grafana_panelleri_manifest_2.yaml](../Manifests/08_observability/grafana_panelleri_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Grafana Birleşik Uyarı Sistemi (Unified Alerting)

Grafana, hem Prometheus metriklerine hem de Loki loglarına göre alarm kurabilen **Unified Alerting** motoruna sahiptir.

### İletişim Noktası (Contact Point) Yapılandırması

Alarmların iletileceği kanalı (Slack) tanımlayan örnek yapılandırma:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [grafana_panelleri_manifest_3.yaml](../Manifests/08_observability/grafana_panelleri_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Loki ile Metrik ve Log Korelasyonu

Grafana'nın en büyük gücü, metrikler ile logları aynı ekranda korele edebilmesidir (Split View). Grafana Explore panelinde logları sorgularken kullanabileceğiniz bazı pratik sorgular:

```logql
# 1. Hata loglarını süzüp JSON içeriğinden durum kodunu çıkarın:
{app="payment-gateway"} | json | status_code >= 500

# 2. İki farklı mikroservisin loglarını zaman ekseninde karşılaştırın:
{app=~"api-gateway|auth-service"} | json | line_format "{{.level}} -> {{.message}}"
```

---

## 7. Grafana Dashboard Yönetimi ve API ile Yedekleme

Dashboard'ları yedeklemek, sürümlemek ve dışa aktarmak için Grafana API'si kullanılabilir:

```bash
# 1. Grafana API'sinden tüm dashboard listesini çekme
curl -s -u admin:SecureGrafanaPass2026! http://localhost:3000/api/search | jq '.[].title'

# 2. Belirli bir panelin JSON şablonunu export edip (yedekleyip) kaydetme
curl -s -u admin:SecureGrafanaPass2026! http://localhost:3000/api/dashboards/uid/k8s-overview-2026 | \
  jq '.dashboard' > my-k8s-dashboard-backup.json
```

> [!TIP]
> **Dashboard Sidecar Mantığı:** Kümeye yeni bir dashboard JSON dosyası eklemek için `grafana-sc-dashboard: "1"` etiketine sahip bir Kubernetes `ConfigMap` nesnesi oluşturmanız yeterlidir. Grafana sidecar aracı bu dosyayı otomatik olarak algılar ve yeniden başlatmaya gerek duymadan Grafana arayüzüne yükler.

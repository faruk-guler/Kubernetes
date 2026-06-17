# Kendi Uygulamamızı Paketleme: Helm Chart Geliştirme

Kubernetes üzerinde bir uygulamayı çalıştırmak için `Deployment`, `Service`, `Ingress`, `ConfigMap` ve `Secret` gibi birçok YAML dosyası hazırlarız. Ancak uygulamanızı farklı ortamlara (Geliştirme - Dev, Test - Staging, Canlı - Production) kurmak istediğinizde büyük bir sorunla karşılaşırsınız.

---

## Statik YAML Çoğaltma Sorunu ve Çözümü

* **Sorun:** Her ortam için ayrı statik YAML dosyaları oluşturursanız, parametrelerde yapacağınız tek bir güncelleme (örneğin bellek limitini artırma veya yeni bir çevre değişkeni ekleme) tüm bu dosyaları tek tek elle güncellemenizi gerektirir. Bu durum hem zaman kaybıdır hem de insan kaynaklı hatalara davetiye çıkarır.
* **Çözüm (Helm):** Helm, Kubernetes dünyasının paket yöneticisidir (apt veya npm gibi). Helm kullanarak manifestolarımızı değişkenler barındıran şablonlara (**templates**) dönüştürürüz. Bu şablonlara gönderilecek ortam bazlı değişkenleri ise tek bir yapılandırma dosyasında (**values.yaml**) toplayarak yönetiriz. Böylece tek bir şablon setiyle yüzlerce farklı ortamı kolayca yönetebiliriz.

---

## 1. Helm Chart Klasör Yapısı

Yeni bir Helm Chart oluşturmak için terminalde `helm create my-app` komutunu çalıştırırız. Bu komut, standartlara uygun aşağıdaki klasör hiyerarşisini otomatik olarak oluşturur:

```
my-app/
├── Chart.yaml          # Chart'ın adı, açıklaması ve versiyon bilgisini tutan dosya
├── values.yaml         # Tüm şablonlarda kullanılacak varsayılan değişkenler
├── charts/             # Bu chart'ın bağımlı olduğu diğer alt chart'lar (subcharts)
├── templates/          # Kubernetes manifest şablonlarının bulunduğu dizin
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl    # Şablonlarda tekrar eden ortak kodları (helpers) barındıran dosya
│   ├── NOTES.txt       # Kurulum tamamlandıktan sonra kullanıcıya gösterilen bilgilendirme metni
│   └── tests/          # Chart kurulumunun başarılı olduğunu test eden podlar
└── .helmignore         # Paketleme sırasında hariç tutulacak dosyalar listesi
```

---

## 2. Chart.yaml Tasarımı

`Chart.yaml`, paketimizin kimlik kartıdır. Burada uygulamanın sürümü (`appVersion`) ile paketimizin sürümü (`version`) ayrı tutulur. Bu ayrım, uygulama kodu değişmese dahi Kubernetes konfigürasyonunu güncelleyip paket sürümünü artırmamızı sağlar.

```yaml
apiVersion: v2
name: my-app
description: "Şirket içi mikroservis uygulaması"
type: application

# SemVer standartlarında versiyonlar
version: 1.2.3             # Helm Chart'ın kendi versiyonu
appVersion: "2.1.0"        # Pod içinde çalışacak uygulamanın versiyonu

maintainers:
- name: Platform Ekibi
  email: platform@company.com

dependencies:
- name: postgresql
  version: "14.x.x"
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled
```

---

## 3. values.yaml ile Değişken Yönetimi

`values.yaml` dosyası, şablonlara enjekte edilecek tüm varsayılan değerleri barındırır. Geliştiriciler kurulum yaparken sadece bu değerleri ezerek (override) kurulumu özelleştirir.

```yaml
replicaCount: 2

image:
  repository: ghcr.io/company/my-app
  tag: ""                  # Boş bırakılırsa Chart.yaml'daki appVersion kullanılır
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

env:
  DATABASE_URL: "postgresql://user:pass@db:5421/db"
```

---

## 4. Şablon Yapısı (Templates) ve Go Template Dili

Helm, şablonları render etmek için Go programlama dilinin template motorunu kullanır. `{{ .Values.degisken }}` ifadesiyle `values.yaml` içindeki verilere erişiriz.

### deployment.yaml Şablon Örneği

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: {{ .Values.service.targetPort }}
        {{- if .Values.env }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
        resources:
          {{- toYaml .Values.resources | nindent 12 }}
```

> [!NOTE]
> **nindent 4** ifadesi, oluşturulan kodun başına 4 karakterlik girinti (indentation) ekler. Kubernetes YAML formatında girintiler hayati önem taşıdığı için bu fonksiyonlar şablon yazımında sıklıkla kullanılır.

---

## 5. _helpers.tpl — Ortak Kod Blokları

Chart içinde tekrar eden ortak etiketler (labels) veya isim türetme kuralları `_helpers.tpl` içinde tanımlanır ve şablonlarda `include` fonksiyonu ile çağrılır:

```
{{/*
Ortak etiketler (Labels)
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
{{ include "my-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/*
Seçici etiketler (Selector Labels)
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

---

## 6. Paketleme ve OCI Registry'de Yayınlama

Helm 3.8+ sürümleriyle birlikte artık chart'larımızı paketleyip doğrudan Docker imajları gibi **OCI (Open Container Initiative)** uyumlu registry'lerde (GitHub Packages, Harbor, Docker Hub) saklayabiliriz.

```bash
# 1. Chart klasörünü paketleme (.tgz uzantılı arşiv üretir)
helm package my-app/ --version 1.2.3

# 2. Registry'de kimlik doğrulama
helm registry login ghcr.io --username $GITHUB_USER --password $GITHUB_TOKEN

# 3. Paketi OCI formatında push etme
helm push my-app-1.2.3.tgz oci://ghcr.io/company/charts

# 4. Başka bir sunucudan OCI paketini çekerek kurma
helm install my-release oci://ghcr.io/company/charts/my-app --version 1.2.3 -n production
```

---

## 7. Doğrulama ve Test Komutları

Geliştirdiğiniz chart'ı uygulamadan önce test etmek için şu yardımcı komutları kullanın:

```bash
# Şablonlardaki sözdizimi (syntax) hatalarını tarama
helm lint my-app/

# Değerleri enjekte ederek nihai YAML çıktısını ekrana yazdırma (Dry-Run)
helm template my-release my-app/ --values my-values.yaml

# Değişiklikleri kurmadan önce cluster'daki mevcut haliye karşılaştırma (Diff)
helm diff upgrade my-release my-app/ --values my-values.yaml
```

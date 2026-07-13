# Helm Chart Geliştirme ve Paketleme Kılavuzu

Bir Kubernetes uygulamasını deploy etmek için `Deployment`, `Service`, `Ingress`, `ConfigMap` ve `Secret` gibi birçok YAML dosyası hazırlarız. Ancak uygulamanızı farklı ortamlara (Geliştirme - Dev, Test - Staging, Canlı - Production) kurmak istediğinizde statik YAML dosyalarının çoğaltılması ve yönetilmesi büyük bir soruna dönüşür.

---

## Statik YAML Çoğaltma Sorunu ve Helm Çözümü

* **Sorun:** Her ortam için ayrı statik YAML dosyaları oluşturursanız, parametrelerde yapacağınız tek bir güncelleme (örneğin bellek limitini artırma veya yeni bir çevre değişkeni ekleme) tüm bu dosyaları tek tek elle güncellemenizi gerektirir. Bu durum hem zaman kaybıdır hem de insan kaynaklı hatalara davetiye çıkarır.
* **Çözüm (Helm):** Helm ile manifestolarımızı değişkenler barındıran şablonlara (**templates**) dönüştürürüz. Bu şablonlara gönderilecek ortam bazlı değişkenleri ise tek bir yapılandırma dosyasında (**values.yaml**) toplayarak yönetiriz. Böylece tek bir şablon setiyle yüzlerce farklı ortamı kolayca yönetebiliriz.

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

### Örnek `Chart.yaml`

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_chart_gelistirme_manifest_3.yaml](../Manifests/09_gitops/helm_chart_gelistirme_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. values.yaml ile Değişken Yönetimi

`values.yaml` dosyası, şablonlara enjekte edilecek tüm varsayılan değerleri barındırır. Kurulum sırasında bu değerler ezilerek (override) kurulum özelleştirilir.

### Örnek `values.yaml`

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_chart_gelistirme_manifest_1.yaml](../Manifests/09_gitops/helm_chart_gelistirme_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. Go Template Dili ile Şablon Yapısı (Templates)

Helm, şablonları çözümlerken Go programlama dilinin template motorunu kullanır. `{{ .Values.degisken }}` ifadesiyle `values.yaml` içindeki verilere erişiriz.

### `templates/deployment.yaml` Şablon Örneği

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [helm_chart_gelistirme_manifest_2.yaml](../Manifests/09_gitops/helm_chart_gelistirme_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

> [!NOTE]
> **nindent 10** ifadesi, oluşturulan kod bloğunun başına 10 karakterlik girinti (indentation) ve yeni bir satır ekler. Kubernetes YAML formatında blok girintileri hayati önem taşıdığı için `nindent` fonksiyonu şablon yazımında en kritik araçtır.

---

## 5. `templates/_helpers.tpl` — Ortak Şablon Yardımcıları

Chart içinde tekrar eden ortak etiketler (labels) veya isim türetme kuralları `_helpers.tpl` içinde tanımlanır ve şablonlarda `include` fonksiyonu ile çağrılır:

```protobuf
{{/*
Uygulama tam adını üret (release adıyla birleştirerek)
*/}}
{{- define "my-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | truncate 63 | cleanSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | truncate 63 | cleanSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | truncate 63 | cleanSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Standart Kubernetes Etiketleri (Labels)
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | truncate 63 | cleanSuffix "-" }}
{{ include "my-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Seçici (Selector) Etiketleri
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

---

## 6. OCI Registry'de Paketleme ve Yayınlama

Helm 3.8+ ile birlikte chart'larınızı paketleyip doğrudan Docker imajları gibi **OCI (Open Container Initiative)** uyumlu registry'lerde (GitHub Packages, Harbor, Artifact Hub) depolayabilirsiniz.

```bash
# 1. Chart klasörünü paketleme (.tgz uzantılı arşiv üretir)
helm package my-app/ --version 1.2.3

# 2. Kayıt defterinde (Registry) kimlik doğrulama yapın
helm registry login ghcr.io --username $GITHUB_USER --password $GITHUB_TOKEN

# 3. Paketi OCI formatında kayıt defterine yükleyin (push)
helm push my-app-1.2.3.tgz oci://ghcr.io/company/charts

# 4. Başka bir sunucudan OCI paketini çekerek kurma
helm install my-release oci://ghcr.io/company/charts/my-app --version 1.2.3 -n production
```

---

## 7. Doğrulama ve Test Komutları

Geliştirdiğiniz chart'ı canlı ortama göndermeden önce mutlaka test edin:

```bash
# 1. Şablonlardaki sözdizimi (syntax) hatalarını tarama
helm lint my-app/

# 2. Değerleri şablonlara enjekte ederek nihai YAML çıktısını ekrana yazdırma (Simülasyon)
helm template my-release my-app/ --values my-values.yaml

# 3. Kümede kurulu olan sürüm ile localdeki güncellemelerin farkını görme (Diff)
# Not: Helm-diff eklentisi gerektirir (helm plugin install https://github.com/databus23/helm-diff)
helm diff upgrade my-release my-app/ --values my-values.yaml
```

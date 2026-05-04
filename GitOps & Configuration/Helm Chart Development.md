# Helm Chart Geliştirme

Hazır chart kullanmayı öğrenmek yeterli değil. Kendi uygulamanı paketlemek, ekibine dağıtmak ve OCI registry'de yayınlamak için Helm chart geliştirmeyi bilmek gerekir.

---

## Chart Yapısı

```bash
helm create my-app
# Oluşturulan yapı:
my-app/
├── Chart.yaml          ← Chart metadata
├── values.yaml         ← Varsayılan değerler
├── charts/             ← Bağımlı chart'lar
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    ← Yeniden kullanılabilir template'ler
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── NOTES.txt       ← Kurulum sonrası gösterilen mesaj
│   └── tests/
│       └── test-connection.yaml
└── .helmignore
```

---

## Chart.yaml

```yaml
apiVersion: v2              # Helm 3 için v2
name: my-app
description: "Company API microservice"
type: application           # application veya library

version: 1.2.3             # Chart versiyonu (SemVer)
appVersion: "2.1.0"        # Uygulamanın versiyonu

maintainers:
- name: Platform Team
  email: platform@company.com

dependencies:
- name: postgresql
  version: "14.x.x"
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled    # values.yaml'da kontrol edilir
- name: redis
  version: "18.x.x"
  repository: https://charts.bitnami.com/bitnami
  condition: redis.enabled
```

---

## values.yaml Tasarımı

```yaml
# Tüm varsayılanlar burada
replicaCount: 1

image:
  repository: ghcr.io/company/my-app
  tag: ""              # Boşsa Chart.yaml'daki appVersion kullanılır
  pullPolicy: IfNotPresent

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  name: ""
  annotations: {}

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts:
  - host: my-app.example.com
    paths:
    - path: /
      pathType: Prefix
  tls: []

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

env: {}
#  DATABASE_URL: postgresql://...
#  REDIS_HOST: redis:6379

postgresql:
  enabled: false          # Bağımlı chart'ı aktif et

redis:
  enabled: false
```

---

## _helpers.tpl — Yeniden Kullanılabilir Template'ler

```
{{/*
Uygulama adını üret
*/}}
{{- define "my-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Tam release adı: release-name + chart-name
*/}}
{{- define "my-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Ortak label'lar
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
{{ include "my-app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/*
Selector label'lar
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

---

## deployment.yaml — Template Örneği

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
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

---

## Helm Test

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "my-app.fullname" . }}-test
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: curlimages/curl:latest
    command: ['curl', '-f', 'http://{{ include "my-app.fullname" . }}:{{ .Values.service.port }}/healthz']
```

```bash
# Test çalıştır
helm test my-release -n production
# Pod/my-app-test PASSED
```

---

## Helm Unittest

```bash
# Plugin kurulumu
helm plugin install https://github.com/helm-unittest/helm-unittest

# Test dosyası
mkdir -p my-app/tests
cat > my-app/tests/deployment_test.yaml << 'EOF'
suite: deployment tests
templates:
- templates/deployment.yaml
tests:
- it: replicas doğru ayarlanmış
  set:
    replicaCount: 3
  asserts:
  - equal:
      path: spec.replicas
      value: 3
- it: HPA varsa replicas yok
  set:
    autoscaling.enabled: true
  asserts:
  - notExists:
      path: spec.replicas
- it: image tag doğru
  set:
    image.repository: ghcr.io/company/app
    image.tag: v2.0.0
  asserts:
  - equal:
      path: spec.template.spec.containers[0].image
      value: ghcr.io/company/app:v2.0.0
EOF

helm unittest my-app/
```

---

## OCI Registry'ye Yayınlama

```bash
# Helm 3.8+ ile OCI desteği
export HELM_EXPERIMENTAL_OCI=1

# Chart'ı paketle
helm package my-app/ --version 1.2.3
# my-app-1.2.3.tgz oluştu

# GitHub Container Registry'ye push
helm registry login ghcr.io \
  --username $GITHUB_USER \
  --password $GITHUB_TOKEN

helm push my-app-1.2.3.tgz oci://ghcr.io/company/charts

# Başka yerde kullan
helm install my-release \
  oci://ghcr.io/company/charts/my-app \
  --version 1.2.3 \
  -n production
```

---

## Chart Lint ve Doğrulama

```bash
# Syntax kontrolü
helm lint my-app/

# Template render et (deploy etmeden gör)
helm template my-release my-app/ \
  --values my-values.yaml \
  -n production | kubectl diff -f -

# Dry-run
helm install my-release my-app/ \
  --dry-run \
  --debug \
  -n production

# chart-testing (CI için)
docker run --rm -it \
  -v $(pwd):/workdir \
  quay.io/helmpack/chart-testing:latest \
  ct lint --all --chart-dirs .
```

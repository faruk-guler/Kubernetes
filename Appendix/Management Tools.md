# Kubernetes Management Tools

Günlük cluster operasyonlarını hızlandıran terminal UI, masaüstü IDE ve web arayüzü araçları.

---

## k9s — Terminal Cluster Yönetimi

```bash
# Kurulum
brew install k9s                        # macOS
choco install k9s                       # Windows
kubectl krew install k9s                # Krew ile

# Başlatma
k9s                                     # Varsayılan context
k9s -n production                       # Namespace ile
k9s --context prod-cluster              # Belirli context
k9s --readonly                          # Salt okunur (kazara silme yok)
k9s --kubeconfig ~/.kube/prod.yaml      # Özel kubeconfig
```

**Temel Navigasyon:**

| Kısayol | İşlev |
|:--------|:------|
| `:po` | Pod listesi |
| `:svc` | Service listesi |
| `:deploy` | Deployment listesi |
| `:ns` | Namespace geç |
| `:no` | Node listesi |
| `:pvc` | PersistentVolumeClaim |
| `:ing` | Ingress |
| `:cm` | ConfigMap |
| `:secret` | Secret |
| `/` | Filtrele |
| `l` | Log görüntüle |
| `s` | Shell bağlan |
| `d` | Describe |
| `e` | Edit |
| `Ctrl+D` | Delete |
| `Ctrl+K` | Kill (force delete) |
| `y` | YAML görüntüle |
| `u` | CPU/Mem kullanımı |
| `0-9` | Namespace geç (0 = tümü) |
| `?` | Tüm kısayollar |

```bash
# k9s skin (tema) ayarı
mkdir -p ~/.config/k9s
# Dracula, Nord, Catppuccin temaları: https://github.com/derailed/k9s/tree/master/skins
curl -L https://raw.githubusercontent.com/catppuccin/k9s/main/dist/mocha.yaml \
  -o ~/.config/k9s/skin.yaml
```

```yaml
# k9s plugin örneği — seçili pod için Trivy taraması
# ~/.config/k9s/plugins.yaml
plugins:
  trivy-scan:
    shortCut: Shift-T
    description: "Trivy ile image tara"
    scopes:
    - pod
    command: bash
    background: false
    args:
    - -c
    - "trivy image $(kubectl get pod $NAME -n $NAMESPACE -o jsonpath='{.spec.containers[0].image}') --severity HIGH,CRITICAL"
```

---

## Lens / OpenLens — Masaüstü Kubernetes IDE

Lens, kubeconfig dosyanızdaki tüm cluster'ları grafik arayüzle yönetmenizi sağlar.

```bash
# OpenLens (ücretsiz, açık kaynak)
brew install --cask openlens            # macOS
choco install openlens                  # Windows
# Veya: https://github.com/MuhammedKalkan/OpenLens/releases

# Mirantis Lens (ticari, daha fazla özellik)
# https://k8slens.dev/
```

**Özellikler:**
- Tüm cluster'ları tek panelden yönet
- Pod log, terminal, describe — grafik arayüzle
- Prometheus/Grafana entegrasyonu (dahili metrik görünümü)
- Helm chart yönetimi
- Multi-cluster context geçişi
- Extension/plugin sistemi

---

## Headlamp — Web Tabanlı Dashboard

Hafif, güvenli, RBAC uyumlu tarayıcı tabanlı Kubernetes arayüzü:

```bash
# Helm ile cluster'a kur
helm repo add headlamp https://headlamp-k8s.github.io/headlamp/
helm install headlamp headlamp/headlamp \
  --namespace kube-system \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=headlamp.company.com

# Yerel erişim (port forward)
kubectl port-forward svc/headlamp -n kube-system 4466:80
# http://localhost:4466

# Token ile giriş
kubectl create serviceaccount headlamp-admin -n kube-system
kubectl create clusterrolebinding headlamp-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:headlamp-admin
kubectl create token headlamp-admin -n kube-system --duration=24h
```

> [!WARNING]
> Headlamp'ı `cluster-admin` yetkisiyle production'da doğrudan açmayın. OIDC (SSO) entegrasyonu yapın veya namespace düzeyinde RBAC uygulayın.

---

## krew — kubectl Plugin Yöneticisi

```bash
# krew kurulumu
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# Plugin ara ve kur
kubectl krew search            # Tüm plugin'ler
kubectl krew install neat      # Temiz YAML çıktısı
kubectl krew install ctx       # Context geçişi (kubectx)
kubectl krew install ns        # Namespace geçişi (kubens)
kubectl krew install tree      # Kaynak hiyerarşisi
kubectl krew install images    # Pod image'larını listele
kubectl krew install df-pv     # PV disk kullanımı
kubectl krew install who-can   # RBAC sorgulama
kubectl krew install stern     # Multi-pod log
kubectl krew install slice     # YAML parçalama

# Güncel tut
kubectl krew upgrade
```

---

## Önemli kubectl Plugin'leri

```bash
# neat — Gereksiz field'ları temizle
kubectl get pod web -o yaml | kubectl neat
kubectl get deployment api -o yaml | kubectl neat > clean.yaml

# tree — Kaynak bağımlılıklarını göster
kubectl tree deployment api -n production
# NAMESPACE   NAME                          READY  REASON  AGE
# production  Deployment/api                -              5d
# production  └─ReplicaSet/api-5d9f8b9c6c  -              5d
# production    ├─Pod/api-5d9f8b9c6c-abc   True           2d

# images — Cluster'daki tüm image'lar
kubectl images -n production
kubectl images -A | grep "ghcr.io/company"

# who-can — RBAC sorgula
kubectl who-can get secrets -n production
kubectl who-can delete pods --all-namespaces

# df-pv — PV disk doluluk oranı
kubectl df-pv -n production
# PVC       VOLUME     CAPACITY  USED   AVAIL  %USED
# data-pvc  pvc-xxx    50Gi      23Gi   27Gi   46%

# stern — Multi-pod log
stern -l app=api -n production --since 1h
stern "api-.*" -n production --output json | jq .message
```

---

## Monokle — YAML Görselleştirme

```bash
# Monokle Desktop
# https://monokle.io/download

# CLI ile manifest doğrulama
npm install -g @monokle/cli
monokle validate ./k8s-manifests/
monokle analyze ./k8s-manifests/ --policy pss-restricted
```

---

## RBAC Lookup — Yetki Sorgulama

Kullanıcı, grup veya ServiceAccount'ların hangi Role/ClusterRole'lere bağlı olduğunu hızlıca sorgular.

```bash
# Kurulum
kubectl krew install rbac-lookup

# Belirli kullanıcının yetkilerini listele
kubectl rbac-lookup jane -k user

# ServiceAccount yetkilerini listele
kubectl rbac-lookup ci-bot -k serviceaccount -n production

# Tüm cluster-admin'leri bul
kubectl rbac-lookup cluster-admin -k role --output wide

# Tüm binding'leri listele
kubectl rbac-lookup --output wide
```

---

## Reloader — ConfigMap/Secret Değişince Otomatik Restart

ConfigMap veya Secret değiştiğinde ilgili Deployment/StatefulSet/DaemonSet'i otomatik rolling restart eder.

```bash
# Helm ile kur
helm repo add stakater https://stakater.github.io/stakater-charts
helm install reloader stakater/reloader \
  --namespace reloader \
  --create-namespace
```

```yaml
# Deployment'a annotation ekle — ConfigMap değişince restart
metadata:
  annotations:
    reloader.stakater.com/auto: "true"     # Tüm ConfigMap/Secret değişikliklerini izle

# veya belirli ConfigMap/Secret'ı izle
    configmap.reloader.stakater.com/reload: "app-config,db-config"
    secret.reloader.stakater.com/reload: "app-secret"
```

```bash
# Reloader durumu
kubectl get deployments -n reloader
kubectl logs -n reloader -l app=reloader -f
```

---

## KubeShark — Kubernetes API Trafik Analizi

Wireshark benzeri, Kubernetes için gerçek zamanlı ağ trafiği yakalama ve analiz aracı.

```bash
# Kurulum
brew install kubeshark    # macOS
# Linux/Windows: https://docs.kubeshark.co/en/install

# Tüm cluster trafiğini izle
kubeshark tap

# Belirli namespace
kubeshark tap -n production

# Belirli pod'lar (regex)
kubeshark tap "api-.*" -n production

# Filtre ile (KFL — KubeShark Filter Language)
# UI'da filtre: http.request.method == "POST" && http.response.statusCode >= 500
```

```bash
# Script ile analiz (Kubernetes için tcpdump alternatifi)
kubeshark tap --dry-run          # Yakalamadan önce test
kubeshark clean                  # Tüm kaynakları temizle
```

> [!TIP]
> KubeShark, servisler arası L7 trafik sorunlarını (yanlış header, body, gRPC hataları) debug etmek için idealdir. `kubectl exec` + tcpdump'tan çok daha güçlüdür.

---

## Araç Karşılaştırması

| Araç | Tür | En İyi Kullanım |
|:-----|:----|:----------------|
| **k9s** | Terminal UI | Hızlı günlük operasyon |
| **Lens/OpenLens** | Masaüstü IDE | Çoklu cluster, uzun süreli çalışma |
| **Headlamp** | Web UI | Ekip paylaşımı, uzak erişim |
| **krew + plugins** | CLI | Otomasyon, script entegrasyonu |
| **Monokle** | Desktop/CLI | YAML analiz, policy doğrulama |
| **RBAC Lookup** | CLI | Yetki denetimi ve audit |
| **Reloader** | Controller | ConfigMap/Secret değişim yönetimi |
| **KubeShark** | Network sniffer | L7 trafik debug ve analiz |

> [!TIP]
> Günlük operasyon için **k9s** vazgeçilmezdir. Ekip içi görünürlük için **Headlamp** (cluster'a deploy et, OIDC ile koru). CI/CD entegrasyonu için **krew plugin'leri** (neat, who-can, images) script'lere ekle.

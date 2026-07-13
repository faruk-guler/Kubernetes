# Rancher Fleet ile Çok Büyük Ölçekli GitOps ve Çoklu Küme Yönetimi

Organizasyonunuzda 5 veya 10 Kubernetes kümesi (cluster) yönetmek ArgoCD veya FluxCD ile oldukça kolaydır. Ancak perakende mağazaları, fabrikalar veya 5G baz istasyonları gibi uç bilişim (**Edge Computing**) senaryolarında, sayıları 1000'i aşan uzak kümenin tek bir merkezden yönetilmesi gerektiğinde geleneksel GitOps araçları ölçekleme sınırlarına ulaşır.

**Rancher Fleet**, tek bir yönetim merkezinden (Hub-Spoke mimarisiyle) binlerce Kubernetes kümesini GitOps prensipleriyle yönetmek için tasarlanmış kurumsal ölçekli bir çoklu küme (multi-cluster) dağıtım motorudur.

---

## 1. Fleet ve ArgoCD Karşılaştırması

| Kriter | Rancher Fleet | ArgoCD |
|:---|:---:|:---:|
| **Küme Ölçeği (Maksimum)** | ⚡ 10.000+ Küme (Edge odaklı) | 100-200 Küme |
| **Bileşen Mimarisi** | Hub-Spoke (Kümeler sadece ajan barındırır) | Merkezi sunucu (Kümelerin api'sine direkt bağlanır) |
| **Kullanıcı Arayüzü (UI)** | Rancher UI ile entegre | Kendine ait görsel UI |
| **Ağ Kesintisi Toleransı** | 🟢 Çok Yüksek (Ajanlar offline-first çalışır) | 🟡 Düşük |
| **Hedef Kullanım Alanı** | Edge, IoT, Çok büyük Kubernetes filoları | Mikroservis dağıtımları, gelişmiş canary akışları |

---

## 2. Fleet Mimarisi Nasıl Çalışır?

```
[ Git Deposundaki Kodlar ]
           │
           ▼
┌──────────────────────────────────────┐
│      Fleet Manager (Merkez Küme)     │  <--- Git'i izler, kaynakları paketler (Bundle)
└──────┬──────────────┬──────────────┬─┘
       │              │              │
       ▼ (Pull)       ▼ (Pull)       ▼ (Pull)
┌─────────────┐┌─────────────┐┌─────────────┐
│  Cluster 1  ││  Cluster 2  ││  Cluster N  │  <--- fleet-agent podları çalışır
│ fleet-agent ││ fleet-agent ││ fleet-agent │
└─────────────┘└─────────────┘└─────────────┘
```

* **Manager (Merkezi Denetleyici):** Git reposundaki değişiklikleri izler ve bunları küçük Kubernetes paketlerine (**Bundle**) dönüştürür.
* **Agent (Filonun Ajanları):** Her hedef kümede çalışan bu hafif pod, merkezi sunucudan kendisine ait Bundle paketini çekerek (Pull-based) yerelde uygular.

---

## 3. Kurulum Adımları

Rancher kullanıyorsanız Fleet otomatik olarak kurulu gelir. Bağımsız (Standalone) olarak kurmak için:

```bash
# 1. Fleet CRD ve Yönetici bileşenlerini kurun
helm repo add fleet https://rancher.github.io/fleet-helm-charts/
helm repo update

helm install fleet-crd fleet/fleet-crd -n fleet-system --create-namespace
helm install fleet fleet/fleet -n fleet-system

# 2. Uzak workload kümelerine ajanları (fleet-agent) kurup merkeze bağlayın:
helm install fleet-agent fleet/fleet-agent \
  -n fleet-system \
  --create-namespace \
  --set apiServerURL="https://my-management-cluster-ip:6443" \
  --set apiServerCA="$(kubectl get secret -n fleet-system fleet-controller-bootstrap-token -o jsonpath='{.data.ca\.crt}' | base64 -d)"
```

---

## 4. GitRepo: Git Deposunu İzleme Tanımı

Git reposundaki kodların hangi etiketlere (labels) sahip kümelere dağıtılacağını belirleyen kaynak tanımı:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [fleet_gitops_manifest_1.yaml](../Manifests/11_multicluster/fleet_gitops_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. ClusterGroup (Küme Grupları)

Kümeleri mantıksal olarak gruplandırmak için **ClusterGroup** tanımlanır. Bu sayede coğrafi veya ortamsal gruplamalar yapılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [fleet_gitops_manifest_2.yaml](../Manifests/11_multicluster/fleet_gitops_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 6. Küme Bazlı Parametre Ezme (fleet.yaml ile Override)

Farklı konumlardaki binlerce mağazaya aynı uygulamayı kurarken, her mağazanın adını veya lokal IP adresini özelleştirmek için manifest klasörünün içine `fleet.yaml` eklenir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [fleet_gitops_manifest_3.yaml](../Manifests/11_multicluster/fleet_gitops_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 7. Helm Chart Dağıtımı

Fleet, harici Helm depolarından veya OCI depolarından paket dağıtımını da destekler:

```yaml
# apps/nginx-ingress/fleet.yaml
chart: ingress-nginx
repo: https://kubernetes.github.io/ingress-nginx
version: 4.8.0
helm:
  values:
    controller:
      replicaCount: 2
```

---

## 8. Edge (Uç Bilişim) Senaryosu ve Çevrimdışı Çalışma Gücü

Perakende mağazaları veya fabrikalardaki Kubernetes kümeleri internet kesintilerine sıklıkla maruz kalır. Fleet, **Offline-First** mimariye sahiptir:

* **Kesinti Anı:** Sunucunun internet bağlantısı koptuğunda, yerel `fleet-agent` son başarılı konfigürasyonu (state) korumaya devam eder. ArgoCD gibi merkezi denetim araçlarında yaşanan bağlantı kopması alarmları ve kararsızlıklar Fleet'te yaşanmaz.
* **Bağlantı Kurulduğunda:** İnternet hattı geri geldiğinde, ajan otomatik olarak Hub sunucuya bağlanarak aradaki farkları (diffs) çeker ve kendini günceller. Düşük bant genişliği (low-bandwidth) tüketimi için paketleri sıkıştırarak taşır.

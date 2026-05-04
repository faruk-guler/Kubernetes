# API Priority and Fairness (APF)

Büyük ve yoğun cluster'larda API Server bazen aşırı yüklenir — tek bir hatalı controller binlerce istek göndererek diğer tüm kullanıcıları etkiler. API Priority and Fairness (APF) bu sorunu çözer: istek önceliklendirme ve adil kuyruk mekanizması.

---

## Neden APF?

```
Eski mekanizma (maxRequestsInFlight):
  Toplam eş zamanlı istek limitini aşınca → 429 Too Many Requests
  Kim reddedilir? Rastgele. Kritik sistem bileşeni de dahil.

APF ile:
  Her istek türü kendi kuyruğuna girer
  Her kuyruk adil paylaşımla hizmet alır
  Önemli istek (kubelet, system) → asla bloke edilmez
  Hatalı controller → sadece kendi kotasını tüketir
```

---

## Temel Kavramlar

```
FlowSchema         → "Bu istek hangi akışa giriyor?"
PriorityLevel      → "Bu akış ne kadar öncelikli, kaç slot alır?"

İstek gelir:
  1. FlowSchema'lardan ilk eşleşene bak (öncelik sırasına göre)
  2. FlowSchema → PriorityLevel gösterir
  3. PriorityLevel'in kuyruğuna gir
  4. Slot müsaitse hemen işle, değilse sıra bekle
```

---

## Hazır FlowSchema'lar

```bash
kubectl get flowschemas
# NAME                           PRIORITYLEVEL    MATCHINGPRECEDENCE
# exempt                         exempt           1       ← system:masters → hiç bloke edilmez
# probes                         exempt           2       ← /healthz, /readyz
# system-leader-election         leader-election  100     ← leader election
# workload-leader-election       leader-election  200
# system-nodes                   node-high        400     ← kubelet'ler
# kube-controller-manager        workload-high    800     ← sistem controller'lar
# kube-scheduler                 workload-high    800     ← scheduler
# kube-system-service-accounts   workload-high    900     ← kube-system SA'ları
# service-accounts               workload-low     9000    ← normal SA'lar
# global-default                 global-default   9900    ← catch-all
# catch-all                      catch-all        10000   ← en son çare
```

```bash
kubectl get prioritylevelconfigurations
# NAME              TYPE      NOMINALCONCURRENCYSHARES
# exempt            Exempt    -          ← limit yok
# leader-election   Limited   10
# node-high         Limited   40
# workload-high     Limited   40
# workload-low      Limited   100
# global-default    Limited   20
# catch-all         Limited   5          ← en az slot
```

---

## PriorityLevelConfiguration

```yaml
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata:
  name: platform-team
spec:
  type: Limited
  limited:
    # Toplam API Server kapasitesinin %20'si
    nominalConcurrencyShares: 20

    # Burst: Anlık olarak kapasiteyi 2x aşabilir
    lendablePercent: 50         # Boştayken diğerlerine ödünç ver
    borrowingLimitPercent: 100  # Diğerlerinden en fazla %100 ödünç al

    limitResponse:
      type: Queue
      queuing:
        queues: 8           # Kaç bağımsız kuyruk? (hashing ile)
        handSize: 6         # Her istek kaç kuyruğu dener?
        queueLengthLimit: 50 # Kuyruk dolunca → 429
```

---

## FlowSchema

```yaml
# Platform ekibinin SA'ları yüksek öncelik alsın
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata:
  name: platform-sa-high-priority
spec:
  matchingPrecedence: 500   # Düşük sayı = daha önce eşleşir

  priorityLevelConfiguration:
    name: platform-team

  distinguisherMethod:
    type: ByUser       # Her kullanıcı kendi slot'unu kullanır (adil)
    # ByNamespace → namespace başına adil dağılım

  rules:
  - subjects:
    - kind: ServiceAccount
      serviceAccount:
        name: platform-controller
        namespace: platform
    - kind: Group
      group:
        name: platform-engineers
    resourceRules:
    - apiGroups: ["*"]
      resources: ["*"]
      verbs: ["*"]
      namespaces: ["*"]
```

---

## APF İzleme

```bash
# APF durumu
kubectl get --raw /metrics | grep apiserver_flowcontrol

# Kuyruk doluluk oranı
kubectl get --raw /metrics | grep "apiserver_flowcontrol_current_inqueue_requests"

# Reddedilen istek sayısı
kubectl get --raw /metrics | grep "apiserver_flowcontrol_rejected_requests_total"
```

```promql
# Prometheus: Reddedilen istekler
rate(apiserver_flowcontrol_rejected_requests_total[5m])

# Ortalama kuyruk bekleme süresi
histogram_quantile(0.99,
  rate(apiserver_flowcontrol_request_wait_duration_seconds_bucket[5m])
)

# Priority level başına aktif istek sayısı
apiserver_flowcontrol_current_executing_requests

# Hangi priority level dolup taşıyor?
apiserver_flowcontrol_current_inqueue_requests > 10
```

---

## Sorun Tespiti

```bash
# API Server yavaş mı? APF kontrolü
kubectl get --raw /debug/api/v1/flowcontrol/dump | python3 -m json.tool

# Hangi istek reddediliyor?
kubectl get events -A | grep "Too Many Requests"

# Kötü davranan controller tespiti
# Yüksek istek üreten SA bul:
kubectl get --raw /metrics | grep flowcontrol | grep "service-accounts" | sort -t= -k2 -n | tail -10

# API Server log'larında reddedilen istekler
kubectl logs -n kube-system kube-apiserver-<node> | grep "429\|flowcontrol"
```

---

## Best Practices

```yaml
# ✅ Kritik controller'lar için özel FlowSchema
# ✅ High-volume SA'ları düşük priority'e al
# ✅ catch-all kuyruğunu izle — doluyorsa genel yük fazla
# ✅ lendablePercent ile esneklik sağla

# ❌ Tüm SA'lara exempt verme
# ❌ nominalConcurrencyShares'i çok yüksek ayarlama (toplam 100 sınırı var)
# ❌ queueLengthLimit'i 0 yapma (kuyruk = anında 429)
```

> [!TIP]
> `kubectl get --raw /debug/api/v1/flowcontrol/dump` çok değerli bir tanı aracıdır. Aktif isteklerin hangi FlowSchema'ya düştüğünü, kuyruk durumunu ve bekleme sürelerini gerçek zamanlı gösterir.

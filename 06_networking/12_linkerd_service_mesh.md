# Linkerd: Dünyanın En Hafif ve Hızlı Service Mesh'i

**Linkerd**, Kubernetes için tasarlanmış, açık kaynaklı ve CNCF (Cloud Native Computing Foundation) tarafından "graduated" statüsüne ulaşmış bir **Service Mesh** çözümüdür. 

Eğer İstio'nun yapılandırma karmaşıklığından ve yüksek kaynak tüketiminden çekiniyorsanız, Linkerd tam aradığınız çözümdür. "Zero-config" (sıfır yapılandırma) felsefesiyle dakikalar içinde kurulur ve devasa bir değer sunar.

---

## 1. Neden Linkerd? (Istio vs. Linkerd)

Servis ağları (Service Mesh) genellikle Control Plane (Kontrol Düzlemi) ve Data Plane (Veri Düzlemi) olarak ikiye ayrılır. 
Istio, veri düzlemi için **Envoy Proxy** kullanırken; Linkerd, Rust dilinde sıfırdan ve sadece bu iş için özel olarak yazılmış **Linkerd2-proxy** (Micro-proxy) kullanır.

| Özellik | Istio | Linkerd |
| :--- | :--- | :--- |
| **Data Plane Proxy** | Envoy (C++) | Linkerd2-proxy (Rust) |
| **Kaynak Tüketimi (Bellek)** | Proxy başına ~50-100MB | Proxy başına ~10-20MB |
| **Gecikme (Latency)** | ~1-2ms | < 1ms (Milisaneyenin altında) |
| **Kurulum Karmaşıklığı** | Yüksek (CRD cehennemi) | Çok Düşük (Sıfır konfigürasyon) |
| **En İyi Kullanım Senaryosu** | Çok kümeli, karmaşık routing kuralları olan devasa yapılar | Güvenlik (mTLS) ve Gözlemlenebilirlik (Observability) arayan standart Kubernetes yapıları |

---

## 2. Linkerd Kurulumu

Linkerd'in kendi CLI aracı, hem kurulumu hem de günlük operasyonları çok basit hale getirir.

### 1. CLI Kurulumu
```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin
```

### 2. Küme Uygunluk Kontrolü (Pre-Flight Check)
Linkerd'i kurmadan önce kümenizin uygunluğunu test edin:
```bash
linkerd check --pre
```

### 3. Kurulum
Control Plane'i kümeye kurun:
```bash
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
```

Kontrol düzleminin ayağa kalktığını doğrulayın:
```bash
linkerd check
```

---

## 3. Linkerd'i Uygulamalara Enjekte Etmek (Mesh into Workloads)

Linkerd, "sidecar" mantığıyla çalışır. Yani podlarınızın içine otomatik olarak bir proxy konteyneri ekler. Bunu yapmanın en kolay yolu, namespace veya deployment seviyesinde anotasyon eklemektir.

### CLI ile Anında Enjeksiyon
Çalışan bir deployment'a proxy eklemek (sıfır kesinti ile yeniden başlatılır):
```bash
kubectl get deploy my-app -o yaml | linkerd inject - | kubectl apply -f -
```

### YAML Tabanlı Enjeksiyon
İlgili Namespace'e veya Deployment'a `linkerd.io/inject: enabled` anotasyonu eklediğinizde proxy otomatik olarak basılır.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-api
  namespace: production
  annotations:
    linkerd.io/inject: enabled
# ...
```

---

## 4. Linkerd Ne Sağlar? (Temel Kazanımlar)

### A. Otomatik mTLS (Kalıcı Şifreleme)
Linkerd proxy'leri arasındaki tüm iletişim (pod'dan pod'a) **varsayılan olarak ve hiçbir ayar yapmadan** karşılıklı TLS (mTLS) ile şifrelenir. 
Bu özellik, Zero Trust (Sıfır Güven) mimarisine geçişin en hızlı yoludur. Uygulama kodunda hiçbir SSL/TLS ayarı yapmanıza gerek kalmaz.

### B. Golden Metrics (Altın Metrikler)
Sistemdeki tüm servislerin Başarı Oranı (Success Rate), İstek Sayısı (RPS) ve Gecikme (Latency) süreleri otomatik ölçülür.

Metrikleri CLI üzerinden canlı izlemek için:
```bash
linkerd stat deploy -n production
linkerd top deploy/web-api -n production
```

### C. Dashboard ve Viz UI
Linkerd, metrikleri görselleştirmek için Grafana ve kendi paneli ile birlikte gelir (Viz eklentisi).
```bash
# Viz eklentisini kur
linkerd viz install | kubectl apply -f -
# Tarayıcıda aç
linkerd viz dashboard
```
Dashboard üzerinde hangi servisin hangi servisle konuştuğunu canlı bir topoloji haritası üzerinden görebilirsiniz.

---

## 5. İleri Seviye Özellikler

- **Traffic Split (Canary Deployments):** SMI (Service Mesh Interface) standartlarını kullanarak, trafiğin %10'unu yeni versiyona, %90'ını eski versiyona (Canary Deploy) çok kolay bir şekilde bölebilirsiniz. Flagger veya Argo Rollouts ile mükemmel entegre olur.
- **Retries ve Timeouts:** Kodunuzu değiştirmeden, başarısız HTTP isteklerini otomatik olarak tekrar denetebilirsiniz (Service Profile ile).

## Özet
Sadece **"Kim kiminle konuşuyor?"** (Observability) ve **"Bu konuşmalar şifrelenmiş mi?"** (Security) sorularına cevap arıyorsanız, İstio kurmak bir tankla sinek avlamaya benzer. **Linkerd**, zarif yapısı, düşük kaynak tüketimi ve sağladığı inanılmaz kolaylıkla modern SRE ekiplerinin birinci tercihidir.

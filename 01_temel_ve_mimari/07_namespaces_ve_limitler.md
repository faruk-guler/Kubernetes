# Namespace, Quota ve Limit Yönetimi

Bir Kubernetes cluster'ını birden fazla ekip veya proje arasında güvenli ve verimli şekilde paylaştırmak için kullanılan mekanizmalardır.

---

## 7.1 Namespaces (İsim Alanları)

Namespace'ler, bir fiziksel cluster içindeki **sanal cluster'lar** gibidir. Nesnelerin (Pod, Service, Deployment) mantıksal olarak ayrılmasını sağlar.

```bash
# Tüm namespace'leri listele
kubectl get ns

# Yeni namespace oluştur
kubectl create ns production

# Mevcut bir objeyi belirli bir namespace'de incele
kubectl get pods -n kube-system

# Namespace sil (İçindeki TÜM kaynaklar silinir!)
kubectl delete ns test-env
```

> [!CAUTION]
> Bir namespace silindiğinde, o namespace'e ait tüm kaynaklar (Pod, Secret, Service) kalıcı olarak silinir. İşlem geri alınamaz.

---

## 7.2 Resource Quota (Kaynak Kotası)

Bir namespace'in toplamda ne kadar CPU, RAM ve Pod kullanabileceğini belirler.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "4"         # Toplam request sınırı
    requests.memory: 8Gi      # Toplam RAM sınırı
    limits.cpu: "10"          # Toplam limit sınırı
    limits.memory: 16Gi
    pods: "20"                # Maksimum pod sayısı
    services: "10"            # Maksimum servis sayısı
```

---

## 7.3 LimitRange (Varsayılan Limitler)

Eğer bir pod'un içinde CPU/RAM limitleri belirtilmemişse, otomatik olarak atanacak varsayılan (default) değerleri belirler.

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-min-max-demo-lr
  namespace: team-alpha
spec:
  limits:
  - default:                # Varsayılan LIMIT
      cpu: 500m
      memory: 512Mi
    defaultRequest:         # Varsayılan REQUEST
      cpu: 100m
      memory: 256Mi
    max:                    # Maksimum verilebilecek değer
      cpu: "2"
      memory: 2Gi
    min:                    # Minimum verilebilecek değer
      cpu: 50m
      memory: 64Mi
    type: Container
```

---

## 7.4 Operasyonel İpuçları (Black Belt)

1.  **Varsayılan Namespace:** Her komutta `-n` yazmamak için varsayılan namespace'i değiştirebilirsiniz:
    ```bash
    kubectl config set-context --current --namespace=production
    ```
2.  **Öncelik:** Eğer bir pod, ResourceQuota sınırlarını aşıyorsa Kubernetes o pod'u oluşturmaz ve `Forbidden` hatası döndürür.
3.  **Temizlik:** Kullanılmayan namespace'lerin (`Terminating` durumunda takılanlar) temizlenmesi için önce içindeki kaynakların (özellikle finalize bekleyenler) temizlenmesi gerekebilir.

---
*← [Probe ve Lifecycle](06_probes_ve_lifecycle.md) | [Ana Sayfa](../README.md)*

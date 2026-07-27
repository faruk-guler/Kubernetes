# Ağ Politikaları Derinlemesine İnceleme (NetworkPolicy Deep Dive)

Kubernetes'te varsayılan ağ davranışı **açık kapı (non-isolated)** modelidir. Yani, küme içindeki herhangi bir pod, başka bir isim alanında (namespace) olsa dahi, diğer herhangi bir pod ile doğrudan ve kısıtlamasız konuşabilir. Bu durum mikroservis mimarilerinde ve çoklu kiracılı (multi-tenancy) sistemlerde ciddi bir güvenlik açığıdır.

Bu açığı kapatmak ve pod'lar arası ağ trafiğini katı kurallarla sınırlamak için **NetworkPolicy (Ağ Politikaları)** kaynaklarını kullanırız.

---

## 1. Ağ Politikalarının Çalışma Mantığı

Ağ politikalarını uygulayabilmek için kümenizde ağ kurallarını işleyebilen bir **CNI (Container Network Interface)** sürücüsünün (örneğin **Cilium** veya **Calico**) kurulu olması gerekir. Sadece `flannel` kullanan kümelerde NetworkPolicy nesneleri oluşturulabilir fakat hiçbir kural uygulanmaz (sessizce es geçilir).

Ağ trafiğini yönetirken iki temel yönü kontrol ederiz:

* **Ingress (Giriş):** Poda dışarıdan gelen (gelen yönlü) trafik.
* **Egress (Çıkış):** Poddan dışarıya giden (giden yönlü) trafik.

> [!IMPORTANT]
> **En Az Yetki Kuralı:** Bir poda herhangi bir NetworkPolicy uygulandığı an, o pod **izole (isolated)** durumuna geçer. Belirtilen izin kuralları dışındaki tüm giriş ve çıkış trafiği otomatik olarak engellenir (Default Deny).

---

## 2. Adım Adım Ağ Politikaları Laboratuvarı

Bu senaryoda, Cilium kurulu bir kümede klasik 3 katmanlı (Frontend -> Backend -> Database) bir uygulamanın ağ güvenliğini adım adım kuracağız.

```
[ Frontend Pod ] ──(Erişim Var)──► [ Backend Pod ] ──(Erişim Var)──► [ Database Pod ]
      │                                    │
      └───────────(ERİŞİM YASAK)───────────┘
```

### Hazırlık Komutları

```bash
# 1. Cilium CNI ile local bir minikube kümesi başlatın
minikube start --network-plugin=cni --cni=cilium

# 2. Çalışma isim alanını (namespace) oluşturun
kubectl create namespace network-policy-tutorial

# 3. Podları oluşturun
kubectl run frontend --image=nginx -l app=frontend --namespace=network-policy-tutorial
kubectl run backend --image=nginx -l app=backend --namespace=network-policy-tutorial
kubectl run database --image=nginx -l app=database --namespace=network-policy-tutorial

# 4. Podları servis olarak dışa açın (port 80)
kubectl expose pod frontend --port 80 --namespace=network-policy-tutorial
kubectl expose pod backend --port 80 --namespace=network-policy-tutorial
kubectl expose pod database --port 80 --namespace=network-policy-tutorial
```

---

## 3. İlk Adım: İsim Alanındaki Tüm Trafiği Kapatma (Default Deny All)

Güvenli bir altyapıda ilk kural her şeyi kapatıp sadece izin verdiklerimizi açmaktır.

### `namespace-default-deny.yaml`

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [networkpolicy_derin_dalis_manifest_1.yaml](../Manifests/07_security/networkpolicy_derin_dalis_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Uygulayalım:

```bash
kubectl apply -f namespace-default-deny.yaml
```

Artık podlar arası tüm trafik kesilmiştir. Frontend podundan backend veya database poduna atılan curl istekleri zaman aşımına (`timeout`) uğrayacaktır:

```bash
# Hata verecektir (Bağlantı engellendi)
kubectl exec -it frontend -n network-policy-tutorial -- curl http://backend
```

---

## 4. İkinci Adım: Trafik Akışını Güvenli Şekilde Açma

Katmanlar arası trafiği kontrollü bir şekilde kurallarla açacağız.

### A. Frontend Politikası (Dış Dünyaya Açık, Sadece Çıkış İzni)

Frontend podunun internetten gelen Ingress (Giriş) isteklerini kabul etmesini ve sadece Backend poduna Egress (Çıkış) yapabilmesini istiyoruz.

#### `frontend-policy.yaml`

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [networkpolicy_derin_dalis_manifest_2.yaml](../Manifests/07_security/networkpolicy_derin_dalis_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### B. Backend Politikası (Sadece Frontend'den Al, Sadece Veritabanına Gönder)

Backend podunun sadece Frontend podundan gelen Ingress isteklerini kabul etmesini ve dışarıya sadece Database poduna Egress yapabilmesini istiyoruz.

#### `backend-policy.yaml`

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [networkpolicy_derin_dalis_manifest_3.yaml](../Manifests/07_security/networkpolicy_derin_dalis_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### C. Database Politikası (Sadece Backend'den Giriş, Dışarıya Kapalı)

Database poduna sadece Backend podunun girmesini istiyoruz. Database podu dışarıya hiçbir istek başlatamaz (Egress yok).

#### `database-policy.yaml`

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [networkpolicy_derin_dalis_manifest_4.yaml](../Manifests/07_security/networkpolicy_derin_dalis_manifest_4.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Politikaları uygulayalım:

```bash
kubectl apply -f frontend-policy.yaml
kubectl apply -f backend-policy.yaml
kubectl apply -f database-policy.yaml
```

---

## 5. Doğrulama Testleri

Kurguladığımız ağ kurallarının doğru çalıştığını aşağıdaki komutlarla test edebiliriz:

```bash
# 1. DOĞRU: Frontend, Backend'e erişebilir mi?
kubectl exec -n network-policy-tutorial -c frontend pods/frontend -- curl -s -I http://backend
# Sonuç: HTTP/1.1 200 OK (Başarılı)

# 2. DOĞRU: Backend, Database'e erişebilir mi?
kubectl exec -n network-policy-tutorial -c backend pods/backend -- curl -s -I http://database
# Sonuç: HTTP/1.1 200 OK (Başarılı)

# 3. YASAK: Frontend, doğrudan Database'e erişebilir mi?
kubectl exec -n network-policy-tutorial -c frontend pods/frontend -- curl --max-time 3 http://database
# Sonuç: curl: (28) Connection timed out (Engellendi!)

# 4. YASAK: Database, Frontend veya Backend'e istek atabilir mi?
kubectl exec -n network-policy-tutorial -c database pods/database -- curl --max-time 3 http://backend
# Sonuç: curl: (28) Connection timed out (Engellendi!)
```

---

## 6. Gelişmiş Seçiciler (Namespace Selector ve CIDR Blokları)

### Namespace Seçici (Namespace Selector)

Farklı bir isim alanındaki podlardan gelen trafiğe izin vermek için hem `namespaceSelector` hem de `podSelector` birlikte kullanılmalıdır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [networkpolicy_derin_dalis_manifest_5.yaml](../Manifests/07_security/networkpolicy_derin_dalis_manifest_5.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

### IP ve CIDR Blok Sınırlandırması (External IP)

Küme dışındaki servislerle konuşurken IP aralıkları belirtebilirsiniz (örneğin şirket veri merkezi veya bulut servisleri):

```yaml
spec:
  egress:
  - to:
    - ipBlock:
        cidr: 192.168.1.0/24   # Bu IP bloğuna izin ver
        except:
        - 192.168.1.50/32      # Bu IP'yi hariç tut (yasakla)
```

---

## 7. Ağ Politikaları Editörü

Ağ politikalarını görselleştirmek ve hata yapmadan tasarlamak için tarayıcınızda [Network Policy Editor](https://editor.networkpolicy.io/) aracını kullanabilirsiniz. Bu araç, kuralların giriş ve çıkış yönlerini çizelge halinde göstererek YAML çıktıları üretir.

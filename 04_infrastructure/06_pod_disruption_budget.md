# PodDisruptionBudget ile Kesintisiz Hizmet Güvencesi (PodDisruptionBudget)

**PodDisruptionBudget (PDB)**, küme bakımı (node drain), sürüm yükseltme (upgrade) veya otomatik düğüm azaltma (autoscaling scale-down) gibi planlı küme operasyonları (voluntary disruptions) sırasında, bir uygulamanın minimum kaç podunun çalışır durumda kalacağını garanti eden bir Kubernetes nesnesidir.

PDB tanımlanmadığında, bir düğüm tahliye edilirken (`kubectl drain`) o düğüm üzerindeki tüm podlar aynı anda silinebilir. Eğer uygulamanın tüm podları aynı düğümde bulunuyorsa, bu durum canlı sistemde anlık **%100 servis kesintisine** yol açar.

---

## 1. Neden Gerekli? (Senaryo Karşılaştırması)

```bash
Senaryo: 3 replica'ya sahip bir Web Uygulaması ve çalışan Düğüm-1 tahliye ediliyor.

[Durum A: PDB TANIMLANMAMIŞ]
  1. 'kubectl drain Düğüm-1' komutu çalıştırılır.
  2. Düğüm-1 üzerindeki uygulamanın tüm podları aynı anda silinir (Eviction).
  3. Yeni podlar diğer düğümlerde ayağa kalkana kadar sistem %100 KESİNTİYE uğrar.

[Durum B: PDB TANIMLI (minAvailable: 2)]
  1. 'kubectl drain Düğüm-1' komutu çalıştırılır.
  2. Kubernetes, PDB kuralını kontrol eder: "Aynı anda en fazla 1 pod silinebilir, 2 pod ayakta kalmalı."
  3. Sadece 1 pod silinir. Kalan 2 pod gelen istekleri karşılamaya devam eder (Sıfır Kesinti).
  4. Silinen pod başka bir düğümde ayağa kalkıp 'Ready' durumuna geldikten sonra, diğer pod silinir.
```

---

## 2. PodDisruptionBudget Yapısı ve YAML Tanımları

PDB, hedeflenen podları `selector` etiketiyle seçer ve koruma kuralını iki farklı parametreden biriyle tanımlar:

* **`minAvailable`:** Kümede en az çalışır durumda olması gereken pod sayısı (sayı veya yüzde).
* **`maxUnavailable`:** Kümede aynı anda en fazla kaç podun devre dışı kalabileceği (sayı veya yüzde).

### Örnek 1: Web Uygulaması İçin Yüzdesel Kural (`maxUnavailable: 20%`)

Toplam pod sayımızın %20'sinden fazlasının aynı anda kesintiye uğramasını engeller:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
spec:
  maxUnavailable: 20%
  selector:
    matchLabels:
      app: web-app
```

### Örnek 2: StatefulSet / Veritabanı İçin Sayısal Kural (`minAvailable: 2`)

3 replica'lı bir veritabanı kümesinde ( quorum korumak için) en az 2 podun sürekli ayakta kalmasını garanti eder:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: db-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: database
```

---

## 3. PDB ve Node Drain Etkileşimi (API Eviction)

Düğüm tahliyesi sırasında PDB kuralı ihlal ediliyorsa, drain işlemi kural sağlanana kadar bekletilir (bloklanır):

```bash
# Bir düğümü bakıma almak için drain etme
kubectl drain k8s-worker-01 --ignore-daemonsets --delete-emptydir-data

# Eğer PDB ihlali yaşanıyorsa terminalde şu hatalar basılır ve drain bekler:
# evicting pod production/web-app-xxxxx
# error when evicting pods/"web-app-xxxxx" : Cannot evict pod as it would violate the pod's disruption budget.
# [Yeni pod başka düğümde Ready olana kadar sistem otomatik olarak beklemeye devam eder]
```

### Acil Durumlarda PDB'yi Bypass Etme (Zorla Drain)

Eğer bir sunucu donanımsal arıza veriyorsa ve PDB kuralı sağlanamadığı için drain kilitlendiyse, tahliyeyi zorlamak için tahliye mekanizması evict yerine delete moduna geçirilebilir:

```bash
kubectl drain k8s-worker-01 --disable-eviction --ignore-daemonsets
```

---

## 4. PDB Olmayan Deployment'ları Tespit Etme Scripti

Canlı ortamda (production) PDB tanımı bulunmayan ve risk teşkil eden Deployment nesnelerini bulmak için şu Bash scriptini kullanabilirsiniz:

```bash
#!/bin/bash
echo "PDB Tanımı Olmayan Canlı Deployment Nesneleri:"
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  # Sadece aktif replica'sı olan deployment'ları seçin
  deploys=$(kubectl get deploy -n $ns --field-selector='status.replicas>0' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  for d in $deploys; do
    # PDB sorgula
    pdb=$(kubectl get pdb -n $ns -o jsonpath="{.items[?(@.spec.selector.matchLabels.app=='$d')].metadata.name}" 2>/dev/null)
    if [ -z "$pdb" ]; then
      echo "⚠️  PDB EKSİK: Namespace: $ns | Deployment: $d"
    fi
  done
done
```

---

## 5. Kritik PDB Anti-Pattern'leri (Yapılmaması Gerekenler)

* **Hata 1: `minAvailable` Değerini Toplam Replica Sayısına Eşitlemek:**

  Eğer 3 replica'lı bir uygulamanız varsa ve `minAvailable: 3` olarak PDB tanımladıysanız, Kubernetes hiçbir podun kapatılmasına izin vermez. Bu durum düğüm tahliyesini (drain) sonsuza kadar kilitler ve otomatik küme güncellemelerini dondurur.

* **Hata 2: Tek Podluk Uygulamada `minAvailable: 1` Yapmak:**

  Tek replica çalışan bir pod için `minAvailable: 1` yapıldığında o düğüm asla drain edilemez. Doğru yaklaşım ya replica sayısını 2'ye çıkarmak ya da `minAvailable: 0` veya `maxUnavailable: 1` olarak tanımlayarak planlı drain'lere izin vermektir.

---

## 6. Kurumsal Ortamlarda PDB Zorunluluğu (Platform Yönetişimi)

Büyük organizasyonlarda geliştiricilerin PDB tanımlamayı unutması, planlı bakım pencerelerinde (düğüm yükseltmeleri, AMI yenilemeleri) istenmeyen mikro kesintilere yol açabilir. Bu riski önlemek için platform mühendisleri iki temel yönetişim yaklaşımı benimser:

1. **Politika Motorları ile Denetim (Kyverno / Gatekeeper):** Canlı (`production`) isim alanlarına gönderilen çok replikalı Deployment veya StatefulSet nesnelerini denetler; eşleşen bir PDB nesnesi bulunmuyorsa dağıtımı engeller (`Enforce`) ya da CI/CD hattına uyarı bildirir.
2. **Kütüphane Şablonları (Helm / Kustomize Library Charts):** Şirket içi standart Helm chart'larında her servis için varsayılan olarak `pdb.enabled: true` ve `maxUnavailable: 1` şablonu standart olarak gömülü sunulur.

*(Politika motorlarıyla kabul denetimi ve kural mekanizmaları için bkz: **Bölüm 08 — Güvenlik ve Politika Motorları**).*

---

## Özet

PodDisruptionBudget (PDB), sistem yöneticilerinin düğüm güncelleme ve bakım işlerini canlı servislerde **kesinti yaratmadan** yapabilmesini sağlayan kritik bir emniyet subabıdır. En iyi pratik olarak, canlı ortamdaki tüm çoğullanmış (multi-replica) iş yükleri için `Toplam Replica - 1` formülüyle (veya yüzdesel olarak `maxUnavailable: 25%`) PDB tanımlarının yapılması şarttır.

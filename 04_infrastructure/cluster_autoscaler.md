# Cluster Autoscaler: Bulut Düzeyinde Düğüm Ölçekleme

HPA veya VPA ile pod kaynaklarını ölçeklendirirken, zamanla pod'larımızın toplam fiziksel gereksinimi (RAM ve CPU) kümedeki düğümlerin (nodes) toplam kapasitesini aşabilir. Bu durumda yeni pod'lar yer bulamaz ve **`Pending`** (beklemede) durumuna geçer.

Bu sorunu çözmek için altyapı düzeyinde sunucu sayısını artıran/azaltan **Cluster Autoscaler** mekanizması kullanılır.

---

## 1. Cluster Autoscaler Nasıl Çalışır?

Cluster Autoscaler, Kubernetes kümesindeki pod'ların durumunu sürekli izler.

* **Ölçek Büyütme (Scale-Up):**
  1. Scheduler'ın kaynak yetersizliği (insufficient CPU/memory) nedeniyle yerleştiremediği ve `Pending` durumuna düşen en az bir pod tespit edilir.
  2. Cluster Autoscaler devreye girerek bulut sağlayıcısının (AWS ASG, GCP Instance Group, Azure Virtual Machine Scale Set) API'sine istek gönderir ve yeni bir düğüm (VM) kiralar.
  3. Yeni düğüm kümeye dahil olduğunda, Kubelet ayağa kalkar ve `Pending` bekleyen pod'lar buraya yerleştirilir.

* **Ölçek Küçültme (Scale-Down):**
  1. Cluster Autoscaler, kaynak tüketimi çok düşük (varsayılan olarak %50'nin altında) olan düğümleri izler.
  2. Eğer o düğüm üzerindeki tüm pod'lar başka düğümlere taşınabiliyorsa, düğüm **tahliye edilir (drained)** ve bulut üzerinden kapatılarak fatura maliyeti düşürülür.

---

## 2. Pod Disruption Budget (PDB) İlişkisi

Cluster Autoscaler ölçek küçültme yaparken veya düğüm bakımlarında pod'ları kapatıp taşımak zorundadır. Ancak çok kritik bir mikroservisin (örneğin ödeme sistemi) tüm kopyalarının aynı anda kapatılması servis kesintisine yol açar.

Bunu engellemek için **PDB (Pod Disruption Budget)** tanımlanır. PDB, "Bu uygulamanın canlıda her zaman en az %80 kopyası çalışır durumda kalmalı" veya "Aynı anda en fazla 1 kopya kesintiye uğrayabilir" şeklinde kurallar koyar. Cluster Autoscaler bu kuralları ihlal edecek düğüm kapatma işlemlerini reddeder.

📌 **Örnek PDB Yapılandırması:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [pod_disruption_budget_manifest_1.yaml](../Manifests/04_infrastructure/pod_disruption_budget_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 3. Ölçek Küçültmeyi Engelleyen Durumlar (Scale-Down Blockers)

Aşağıdaki durumlarda Cluster Autoscaler, maliyeti düşürmek istese bile ilgili düğümü kapatamaz:

* Düğümde çalışan pod'lar bir **PDB** kuralı tarafından sıkı sıkıya korunuyorsa ve kapatıldığında PDB ihlal edilecekse.
* Düğümde `controller` (Deployment, ReplicaSet, StatefulSet) tarafından yönetilmeyen **"çıplak" (naked) pod'lar** çalışıyorsa.
* Düğümde yerel disk kullanan (`EmptyDir` veya `HostPath` volume) pod'lar bulunuyorsa ve veri kaybı riski varsa.
* Pod'lar üzerinde `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` annotation'ı tanımlanmışsa.

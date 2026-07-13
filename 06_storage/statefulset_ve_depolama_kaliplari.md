# StatefulSet ve Depolama Kalıpları

**StatefulSet**, podların kimliğini (isim, ağ kimliği ve disk) sabit tutan ve durumlu (stateful) uygulamalar için tasarlanmış özel bir Kubernetes iş yükü (workload) türüdür. Veritabanları, mesaj kuyrukları (Kafka, RabbitMQ) ve dağıtık koordinasyon sistemleri (Zookeeper) gibi uygulamalar için zorunludur.

---

## 1. StatefulSet vs Deployment Karşılaştırması

| Kriter | Deployment | StatefulSet |
| :--- | :--- | :--- |
| **Pod İsimlendirmesi** | Rastgele karakterler (`web-7f8b4d-xkjl9`) | Sıralı ve sabit indeksler (`db-0`, `db-1`, `db-2`) |
| **Başlatma Sırası** | Paralel olarak başlatılır. | Sıralı olarak başlatılır (0 ──► 1 ──► 2). |
| **Durdurma Sırası** | Paralel olarak kapatılır. | Ters sıra ile kapatılır (2 ──► 1 ──► 0). |
| **Ağ Kimliği** | Geçicidir, ClusterIP arkasında gizlenir. | Sabit ve kararlıdır (Headless Service ile). |
| **Depolama (Storage)** | Ortak bir diski veya geçici alanı paylaşırlar. | Her podun kendine özel PVC'si bulunur (`volumeClaimTemplates`). |

---

## 2. Headless Service ve Kararlı Ağ Kimliği

StatefulSet podlarının IP adresleri çöküp yeniden başladıklarında değişse bile, küme içindeki DNS isimleri (hostname) asla değişmez. Bunu sağlamak için bir **Headless Service (ClusterIP adresi olmayan servis)** kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [statefulset_ve_depolama_kaliplari_manifest_2.yaml](../Manifests/06_storage/statefulset_ve_depolama_kaliplari_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu headless servis sayesinde, StatefulSet altındaki her pod şu sabit DNS adresi üzerinden doğrudan erişilebilir hale gelir:
`<pod-adi>.<headless-servis-adi>.<namespace>.svc.cluster.local` (Örn: `db-0.db-service-headless.production.svc.cluster.local`).

---

## 3. `volumeClaimTemplates` ile Otomatik PVC Oluşturma

StatefulSet'in en kritik özelliği, her pod kopyası için şablona uygun benzersiz bir PVC'yi otomatik olarak oluşturmasıdır. Pod silinip başka bir düğümde tekrar ayağa kalktığında, Kubernetes otomatik olarak **eski düğümde bıraktığı aynı PVC diski** bulur ve pod'a tekrar bağlar.

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [statefulset_ve_depolama_kaliplari_manifest_1.yaml](../Manifests/06_storage/statefulset_ve_depolama_kaliplari_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

Bu manifest 3 adet pod (`mysql-cluster-0`, `mysql-cluster-1`, `mysql-cluster-2`) ve bunlara bağlı 3 adet bağımsız PVC (`mysql-data-mysql-cluster-0`, `mysql-data-mysql-cluster-1`, `mysql-data-mysql-cluster-2`) oluşturur.

---

## 4. Ölçek Küçültme (Scale Down) ve Veri Güvenliği

StatefulSet replika sayısı azaltıldığında (Örn: 3'ten 1'e düşürüldüğünde), podlar sırayla silinir ancak oluşturulmuş olan **PVC diskleri silinmez, koruma amacıyla kümede bırakılır**. Bu, veri kayıplarını önlemek için tasarlanmış yerleşik bir güvenlik mekanizmasıdır. Eğer verilerin tamamen silinmesi isteniyorsa, PVC'lerin elle silinmesi gerekir:

```bash
# Ölçek düşürme işlemi
kubectl scale statefulset mysql-cluster --replicas=1

# Silinmeyen PVC'leri listeleme ve elle temizleme
kubectl get pvc -n production
kubectl delete pvc mysql-data-mysql-cluster-2 mysql-data-mysql-cluster-1
```

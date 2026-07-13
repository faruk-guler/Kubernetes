# Topology Spread Constraints: Dengeli ve Güvenli Pod Dağıtımı

Yüksek erişilebilirlik (HA) sağlamak için pod'ların kümedeki düğümlere ve bölgelere (availability zones) dengeli bir şekilde dağıtılması çok önemlidir. 

Eskiden bunu yapmak için Pod Anti-Affinity kuralları kullanılıyordu; fakat Anti-Affinity "ya hep ya hiç" (binary) mantığıyla çalıştığı için büyük kümelerde esneklik sağlamıyordu. Modern Kubernetes dünyasında bu dengeli dağıtımı **Topology Spread Constraints** nesneleri ile sağlarız.

---

## 1. Temel Kavramlar

Topology Spread Constraints, pod'ları tanımlanan topoloji etki alanlarına (topology domains) dengeli yaymak için 4 temel parametre kullanır:

* **`maxSkew`:** Farklı etki alanlarındaki (örneğin iki farklı kullanılabilirlik bölgesi) pod sayıları arasındaki izin verilen maksimum farkı (dengesizliği) belirtir. Genellikle `1` olarak ayarlanır.
* **`topologyKey`:** Dağıtımın hangi düzeyde yapılacağını belirleyen etiket anahtarıdır.
  - `topology.kubernetes.io/zone` (Bölgeler arası dengeli dağıtım)
  - `kubernetes.io/hostname` (Düğümler/Makineler arası dengeli dağıtım)
* **`whenUnsatisfiable`:** Eğer kural tam olarak sağlanamıyorsa (örneğin yeterli düğüm yoksa) ne yapılacağını belirler:
  - `DoNotSchedule` (Sert Kural): Pod'u zamanlama (Pending kalır).
  - `ScheduleAnyway` (Yumuşak Kural): Dengesizliği kabul et ve pod'u yine de bir yere yerleştir (ancak dengeli olanı önceliklendir).
* **`labelSelector`:** Dağıtımı kontrol edilirken hangi pod'ların sayılacağını belirleyen etiket seçicidir.

---

## 2. Çalışma Örneği: maxSkew Hesaplaması

Diyelim ki 3 farklı kullanılabilirlik bölgesine (Zone-A, Zone-B, Zone-C) sahibiz. `maxSkew: 1` olacak şekilde 5 pod dağıtmak istiyoruz:

* **Doğru Dağıtımlar:**
  - `2 - 2 - 1` (Skew = 2 - 1 = 1. Kurala Uygun)
  - `3 - 1 - 1` (Skew = 3 - 1 = 2. Kurala UYGUN DEĞİL!)
* **Nasıl Dağıtılır?** Scheduler pod'ları bölgelere `2-2-1` şeklinde dağıtacaktır. `3-1-1` yapısına izin vermeyecektir çünkü en dolu bölge ile en boş bölge arasındaki fark (skew) 2'dir.

---

## 3. Örnek Yapılandırma Manifesti

Aşağıda, pod'ları hem bölgeler (zones) hem de düğümler (hosts) düzeyinde dengeli dağıtmak için ikili `topologySpreadConstraints` tanımlanmış örnek bir deployment manifesti bulunmaktadır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [topology_spread_constraints_manifest_1.yaml](../Manifests/01_core/topology_spread_constraints_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

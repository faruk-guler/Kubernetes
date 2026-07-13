# Karmada ile Kurumsal Çoklu Küme (Multi-Cluster) Federasyonu ve Yönetimi

Büyük ölçekli kurumsal altyapılarda, tüm uygulamaları tek bir devasa Kubernetes kümesinde çalıştırmak ciddi bir risk yönetimi açığı oluşturur. Bu nedenle günümüz altyapı tasarımlarında çoklu küme (Multi-Cluster) mimarileri standarttır.

Kümeleri tek tek bağımsız yönetmenin yarattığı operasyonel yükü çözmek amacıyla, CNCF projesi olan **Karmada**, binlerce Kubernetes kümesini tek bir "Kontrol Düzlemi (Control Plane)" üzerinden, standart Kubernetes API'sine sadık kalarak yönetmenizi sağlar.

---

## 1. Neden Çoklu Küme Mimarisi?

* **Hata Etki Alanını Daraltma (Blast Radius):** Tek bir kümede yaşanacak ağ veya DNS çökmesi tüm şirketi etkiler. Çoklu kümede ise bir küme çökerse diğerleri çalışmaya devam eder.
* **Düşük Gecikme Süresi (Latency):** Kullanıcılara coğrafi olarak en yakın konumdaki (Örn: Avrupa, Asya, Amerika) kümeden hizmet verilmesi.
* **Yasal Uyum (Compliance/GDPR):** Ülkelerin yasal kuralları gereği, yerel müşteri verilerinin ülke sınırları dışındaki sunucularda barındırılamaması.
* **Ölçek Sınırları (Scale Limits):** Tek bir Kubernetes kümesinin düğüm (node) ve pod kapasite sınırlarını aşan devasa iş yükleri.

---

## 2. Karmada Kurulumu ve Küme Katılımı

Karmada kontrol düzlemini yerel olarak kurmak ve yönetici CLI aracını yüklemek için:

```bash
# 1. Karmada CLI aracını kurun
curl -s https://raw.githubusercontent.com/karmada-io/karmada/master/hack/install-cli.sh | sudo bash

# 2. Karmada Kontrol Düzlemini Başlatın
karmadactl init

# 3. Workload kümelerini Karmada kontrolüne dahil edin (Join)
karmadactl join cluster-europe --kubeconfig=/root/.kube/config --member-context=member1
karmadactl join cluster-asia --kubeconfig=/root/.kube/config --member-context=member2
```

---

## 3. PropagationPolicy (İş Yükü Yayılım Politikası)

Karmada'da standart bir Kubernetes Deployment nesnesi oluşturduğunuzda, bu nesnenin hangi workload kümelerine, hangi kuralla (Örn: Eşit dağıt, sadece Avrupa'ya dağıt vb.) gönderileceğini **PropagationPolicy** CRD nesnesi belirler.

### Örnek Dağıtım Kuralı (Avrupa ve Asya Kümelerine Dağıt)

> 📄 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [karmada_coklu_kume_manifest_1.yaml](../Manifests/11_multicluster/karmada_coklu_kume_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 4. OverridePolicy (Küme Bazlı Yapılandırma Ezme/Yama)

Her kümeye aynı YAML'ı göndermek istesek de, bazı kümelerde (Örn: Asya kümesi) veritabanı IP adresi veya imaj etiketleri farklı olmak zorundadır. Bunu yönetmek için **OverridePolicy** kullanılır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [karmada_coklu_kume_manifest_2.yaml](../Manifests/11_multicluster/karmada_coklu_kume_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. Kümeler Arası Ağ Entegrasyonu

Karmada ile dağıtılan podların farklı kümeler üzerinden birbiriyle konuşması için **Submariner** ağı entegre edilir. Submariner, Wireguard/IPSec tünelleri kurarak kümeler arası pod IP'lerinin yönlendirilmesini sağlar.
*(Detaylı ağ ve DNS yapılandırmaları için bkz: [kumeler_arasi_ag.md](kumeler_arasi_ag.md))*

---

## 6. Global Load Balancing (Küresel Yük Dengeleme)

Karmada, birden fazla kümede koşan uygulamalarınızın önüne tek bir ortak giriş noktası koymak için **MultiClusterIngress (MCI)** özelliğini sunar.

MCI, bulut sağlayıcının (Örn: AWS Route53 GeoDNS veya Anycast IP) küresel yük dengeleyicisi ile konuşarak, kullanıcının DNS sorgusunu coğrafi olarak en yakın ve sağlıklı çalışan Kubernetes kümesine (Cluster) yönlendirir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [karmada_coklu_kume_manifest_3.yaml](../Manifests/11_multicluster/karmada_coklu_kume_manifest_3.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

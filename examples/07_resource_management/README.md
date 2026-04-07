# 📊 Bölüm 7: Kaynak Yönetimi (Resource Management) Örnekleri

Bu dizin, Kubernetes içerisindeki CPU/RAM verimliliği, önceliklendirme ve otomatik ölçeklendirme örneklerini içerir.

## 📄 Dosyalar

| Dosya | Açıklama |
|:---|:---|
| quota.yaml | Namespace bazlı toplam kaynak limitleri (ResourceQuota) |
| limitrange.yaml | Pod/Container bazlı varsayılan kaynak limitleri |
| priorityclass.yaml | Pod önceliklendirme (Kritik iş yükleri için) |
| hpa.yaml | Yatayda otomatik ölçeklendirme (Horizontal Pod Autoscaler) |
| vpa.yaml | Dikeyde otomatik ölçeklendirme (Vertical Pod Autoscaler) |

> [!TIP]
> 2026 standartlarında, statik ölçeklendirme yerine **KEDA** (Event-driven) ve node seviyesinde **Karpenter** (AWS) veya **Cilium Mesh** gibi daha akıllı sistemler tercih edilmektedir.

---
*← Geri*

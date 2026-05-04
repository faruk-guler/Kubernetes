# BOOK_RULES — Kubernetes Mastery

---

## İçerik Kuralları

### ✅ Girer

- Doğrudan Kubernetes API veya CNCF ekosistemiyle ilgili konular
- K8s üzerinde çalışan araçlar (Helm, ArgoCD, Cilium, Kyverno…)
- Image hazırlama — K8s'e deploy için gerekli (Dockerfile, multi-arch, registry)
- Cluster kurulumu ve operasyonu

### ❌ Girmez

| Girmez | Neden |
|:-------|:------|
| Genel yazılım mimarisi (Saga, CQRS, Microservices theory) | K8s'e özgü değil |
| Container/Docker öğreticisi | Ön koşul — okuyucu zaten bilir |
| Genel Linux / algoritma | Tamamen konu dışı |
| Deprecated/kaldırılmış araçlar | `dockershim`, `PSP`, `Heapster`, `kube-dns` |
| Eski Kubernetes runtime olarak Docker | K8s 1.24'ten beri `containerd` |

---

## Format Kuralları

- **Encoding:** UTF-8, LF — `.editorconfig` zorluyor
- **Cross-link yok:** Dosyalar arası `*→ Bkz:*` veya `*← [...]` satırları yasak
- **Her doküman bağımsız:** Link olmadan okunabilmeli
- **Image tag:** `latest` yasak — `nginx:1.27.0` gibi sabit versiyon
- **YAML:** Gerçek production değerleri, `<YOUR_VALUE>` placeholder değil

---

## Teknoloji Kuralları

| Kategori | Kullan | Kullanma |
|:---------|:-------|:---------|
| Runtime | `containerd`, `CRI-O` | Docker runtime |
| CNI | Cilium (eBPF) | Flannel (prod için yetersiz) |
| Ingress | Gateway API v1 | Eski Ingress (deprecated yolunda) |
| GitOps | ArgoCD, Flux v2 | Manuel `kubectl apply` |
| Policy | Kyverno, CEL | PSP (kaldırıldı 1.25) |
| Image tag | Sabit versiyon | `latest` |

# Sorun Giderme Akışları (Troubleshooting Flows)

Kubernetes cluster'ında bir sorun yaşandığında, kaotik denemeler yerine sistematik bir yaklaşım izlemek çözüm süresini %80 oranında kısaltır.

---

## 8.0 Hata Ayıklama Hiyerarşisi

Bir sorun olduğunda şu sıralamayı izleyin:
1.  **Pod Katmanı:** Pod çalışıyor mu? Loglar ne diyor?
2.  **Servis Katmanı:** Servis podlara ulaşıyor mu? Endpoint'ler dolu mu?
3.  **Ağ Katmanı:** DNS çözülüyor mu? CNI (Cilium) sağlıklı mı?
4.  **Altyapı Katmanı:** Node'lar Ready mi? Disk/RAM doluluğu var mı?

---

## 8.1 Pod Seviyesinde Sorun Giderme

### Adım 1: Pod Durumunu Kontrol Et
```bash
kubectl get pods -A
```
- **ImagePullBackOff:** İmaj bulunamadı veya yetki sorunu (Check `imagePullSecrets`).
- **CrashLoopBackOff:** Uygulama başlıyor ama hemen çöküyor (Check `kubectl logs`).
- **Pending:** Kaynak yetersiz veya Scheduler node bulamıyor (Check `kubectl describe`).

### Adım 2: Describe ve Olaylar (Events)
```bash
kubectl describe pod <pod-adi>
# En alt kısımdaki "Events" bölümü hata sebebini açıklar.
```

---

## 8.2 Node Seviyesinde Sorun Giderme

Eğer node `NotReady` durumundaysa:
1.  **Kubelet Durumu:** Node'a SSH yapın ve servisi kontrol edin:
    ```bash
    systemctl status kubelet
    journalctl -u kubelet -f
    ```
2.  **Disk ve RAM:**
    ```bash
    df -h
    free -m
    ```
3.  **Swap:** `swapoff -a` yapıldığından emin olun (kubelet swap sevmez).

---

## 8.3 Servis ve Ağ Sorunları

Uygulama çalışıyor ama erişilemiyorsa:
1.  **Endpoint Kontrolü:** Servis podları bulabilmiş mi?
    ```bash
    kubectl get endpoints <service-adi>
    # Eğer boşsa (none), labellar çakışmıyordur.
    ```
2.  **DNS Testi:**
    ```bash
    kubectl exec -it <pod-adi> -- nslookup kubernetes.default
    ```
3.  **Cilium/Hubble (2026):** Ağ paketlerinin nerede düştüğünü görmek için:
    ```bash
    hubble observe --pod <pod-adi>
    ```

---

## 8.4 Black Belt: En Hızlı Tanı Komutları

```bash
# Crash olan podların loglarını önceki restarttan oku
kubectl logs <pod-adi> --previous

# Tüm cluster'daki ERROR loglarını tarat
kubectl get pods -A | grep -v Running

# Node üzerindeki process'leri ve kubelet loglarını master'dan izle
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion

# Zorla (Force) silme (Pod Terminating'de takılırsa)
kubectl delete pod <pod-adi> --grace-period=0 --force
```

---
*← [Ana Sayfa](../README.md)*

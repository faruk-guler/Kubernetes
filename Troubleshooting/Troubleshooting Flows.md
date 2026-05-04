# Sorun Giderme Akışları (Troubleshooting Flows)

Kubernetes cluster'ında bir sorun yaşandığında kaotik denemeler yerine sistematik yaklaşım çözüm süresini drastik kısaltır. Bu belge katmandan katmana inen hata ayıklama hiyerarşisini sunar.

---

## Hata Ayıklama Hiyerarşisi

```
1. Pod Katmanı       → Pod çalışıyor mu? Log ne diyor?
2. Servis Katmanı    → Endpoint'ler dolu mu? Selector eşleşiyor mu?
3. Ağ Katmanı        → DNS çözülüyor mu? NetworkPolicy engelliyor mu?
4. Node Katmanı      → Node Ready mi? Kaynak yeterli mi?
5. Control Plane     → API Server, Scheduler, Controller-Manager sağlıklı mı?
```

---

## Pod Seviyesi — Durum Okuma Rehberi

```bash
kubectl get pods -n production -o wide
```

| Status | Anlam | İlk Bakılacak Yer |
|:-------|:------|:------------------|
| `Pending` | Hiç başlamadı | `kubectl describe pod` → Events |
| `ImagePullBackOff` | Image çekilemedi | Image adı, imagePullSecrets, registry erişimi |
| `CrashLoopBackOff` | Başlıyor ama çöküyor | `kubectl logs --previous` |
| `OOMKilled` | Bellek limiti aşıldı | `limits.memory` artır |
| `Evicted` | Node kaynaksız → pod'u çıkardı | Node disk/memory durumu |
| `Terminating` | Silinemiyor | `kubectl delete pod --grace-period=0 --force` |
| `Init:0/1` | Init container bekliyor | `kubectl logs pod -c init-container-name` |
| `ContainerCreating` | Volume/secret bekliyor | Events'e bak |

```bash
# Detaylı pod incelemesi
kubectl describe pod <pod-adi> -n <namespace>
# "Events" bölümü — en son hata mesajı buradadır

# Log (çalışıyorsa)
kubectl logs <pod-adi> -n <namespace> --tail=50 -f

# Önceki container'ın logu (CrashLoop için kritik)
kubectl logs <pod-adi> -n <namespace> --previous

# Çok container varsa
kubectl logs <pod-adi> -n <namespace> -c <container-adi>

# Pod içine gir
kubectl exec -it <pod-adi> -n <namespace> -- /bin/sh
```

---

## Servis & Endpoint Sorunları

Uygulama çalışıyor ama erişilemiyorsa:

```bash
# 1. Servis endpoint'leri dolu mu?
kubectl get endpoints <servis-adi> -n production
# Boşsa (none) → Selector label uyuşmazlığı

# 2. Selector kontrolü
kubectl get svc <servis-adi> -n production -o yaml | grep -A5 selector
kubectl get pods -n production --show-labels | grep <label>

# 3. Servis porta erişim testi
kubectl run test --image=busybox:1.36 --rm -it --restart=Never -- \
  wget -qO- http://<servis>.<namespace>.svc.cluster.local:<port>/health

# 4. Port forward ile doğrudan pod testi
kubectl port-forward pod/<pod-adi> 8080:8080 -n production
curl http://localhost:8080/health
```

---

## Ağ & DNS Sorunları

```bash
# DNS test pod'u başlat
kubectl run dns-test \
  --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --restart=Never -it --rm -- bash

# Pod içinde:
nslookup kubernetes.default              # K8s internal DNS
nslookup my-service.production.svc.cluster.local
nslookup google.com                      # Upstream DNS
dig @10.96.0.10 my-service.production.svc.cluster.local

# CoreDNS pod'ları sağlıklı mı?
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

# NetworkPolicy engelliyor mu? (Cilium/Hubble ile)
hubble observe --pod production/<pod-adi> --verdict DROPPED -f
```

---

## Node Sorunları

```bash
# Node durumu
kubectl get nodes -o wide
kubectl describe node <node-adi>

# NotReady nedenini bul
kubectl get node <node-adi> -o jsonpath='{.status.conditions}' | jq .

# Node üzerinde (SSH ile)
systemctl status kubelet
journalctl -u kubelet -f --since "10 minutes ago"

# Kaynak kullanımı
kubectl top nodes
df -h          # Disk doluluk
free -m        # Bellek
swapon -s      # Swap aktif mi? (olmamalı)

# Node'u bakıma al (pod'ları taşı)
kubectl drain <node-adi> --ignore-daemonsets --delete-emptydir-data
# Bakım sonrası geri getir
kubectl uncordon <node-adi>
```

---

## Control Plane Sorunları

```bash
# Static pod'lar sağlıklı mı?
kubectl get pods -n kube-system | grep -E "apiserver|controller|scheduler|etcd"

# API Server logları
kubectl logs -n kube-system kube-apiserver-<node> --tail=50

# etcd sağlığı
kubectl exec -n kube-system etcd-<node> -- \
  etcdctl endpoint health \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# etcd üye listesi
kubectl exec -n kube-system etcd-<node> -- \
  etcdctl member list \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/peer.crt \
  --key=/etc/kubernetes/pki/etcd/peer.key

# Scheduler — neden pod atanmıyor?
kubectl get events -n production --field-selector reason=FailedScheduling
```

---

## Kaynak Yetersizliği Senaryoları

```bash
# CPU/Memory request > limit olan pod'lar
kubectl describe nodes | grep -A5 "Allocated resources"

# Namespace kaynak kullanımı
kubectl top pods -n production --sort-by=memory
kubectl top pods -n production --sort-by=cpu

# Resource quota durumu
kubectl describe resourcequota -n production

# LimitRange varsayılan değerleri
kubectl describe limitrange -n production

# Pending pod'ların neden schedule edilemediğini gör
kubectl get events -A --field-selector reason=FailedScheduling | tail -20
```

---

## Black Belt: En Hızlı Tanı Seti

```bash
# Tüm namespace'lerde sorunlu pod'lar
kubectl get pods -A | grep -vE "Running|Completed"

# Son 1 saatteki Warning event'leri
kubectl get events -A --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -30

# Bir pod'un tüm yaşam döngüsü
kubectl get events -n production \
  --field-selector involvedObject.name=<pod-adi> \
  --sort-by='.lastTimestamp'

# Önceki restart'tan log oku
kubectl logs <pod-adi> -n production --previous --tail=100

# Canlı kaynak değişikliklerini izle
kubectl get pods -n production -w

# Force delete (Terminating'de takılı pod)
kubectl delete pod <pod-adi> -n production --grace-period=0 --force

# Node problemi — kubelet logları (systemd)
journalctl -u kubelet --since "1 hour ago" -p err

# Cluster geneli sağlık özeti
kubectl get componentstatuses 2>/dev/null || \
  kubectl get pods -n kube-system -o wide
```

---

## Acil Durum Checklist

```
□ kubectl get pods -A → Running olmayanlar var mı?
□ kubectl get nodes   → NotReady node var mı?
□ kubectl top nodes   → Kaynak tükenmesi var mı?
□ kubectl get events -A --field-selector type=Warning → Son hatalar
□ CoreDNS pods çalışıyor mu?
□ etcd endpoint health sağlıklı mı?
□ Node disk doluluk < %85?
□ Network policy gereksiz bir şeyi blokluyor mu?
```

> [!TIP]
> `kubectl describe pod` komutundaki **Events** bölümü vakaların %80'ini açıklar. Her sorun incelemesinde ilk bakılacak yer burasıdır.

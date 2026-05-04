# Debug Toolkit

Kubernetes'te sorun gidermek için en güçlü araçların tam rehberi. Standart `kubectl` komutlarının ötesine geçen, gerçek üretim sorunlarını çözen teknikler.

---

## kubectl debug — Ephemeral Container ile Canlı Debug

Distroless veya minimal image kullanan container'larda shell yoktur. Ephemeral container ile çalışan pod'a debug aracı enjekte edilebilir.

```bash
# Çalışan pod'a debug container ekle
kubectl debug -it <pod-adı> \
  --image=nicolaka/netshoot \
  --target=<container-adı>

# Kendi kopyasını oluştur (pod değiştirilmez, kopya açılır)
kubectl debug <pod-adı> -it \
  --image=ubuntu \
  --copy-to=debug-pod \
  --share-processes

# Debug bittikten sonra temizle
kubectl delete pod debug-pod
```

### Popüler Debug Image'ları

| Image | İçerik |
|:------|:-------|
| `nicolaka/netshoot` | curl, dig, nmap, tcpdump, iperf, netstat |
| `busybox` | Minimal — wget, nslookup, ping |
| `curlimages/curl` | Sadece curl |
| `alpine` | Hafif, apk ile paket kurulabilir |
| `ubuntu` | Tam araç seti, apt |

---

## kubectl Node Debug

Node üzerinde doğrudan çalışan araçları SSH gerektirmeden kullanmak için:

```bash
# Node'a privileged container aç
kubectl debug node/<node-adı> -it --image=ubuntu

# Container içinde node'un dosya sistemi /host altında
chroot /host   # Node'un root dosya sistemine geç
systemctl status kubelet
journalctl -u kubelet -n 100
crictl ps
```

---

## crictl — Container Runtime Aracı

API Server çalışmadığında bile container'ları yönetmek için:

```bash
# Çalışan container'lar
crictl ps
crictl ps -a      # Durdurulmuş container'lar dahil

# Container logları
crictl logs <container-id>
crictl logs --tail=50 <container-id>

# Pod listesi
crictl pods
crictl pods --namespace kube-system

# Image listesi
crictl images
crictl rmi <image-id>         # Image sil
crictl rmi --prune            # Kullanılmayan image'ları sil

# Container içine gir
crictl exec -it <container-id> /bin/sh

# Container inspect
crictl inspect <container-id> | jq '.info.runtimeSpec.linux.namespaces'
```

---

## tcpdump — Ağ Trafiği Yakalama

```bash
# Önce netshoot container'ı pod'a ekle
kubectl debug -it <pod> --image=nicolaka/netshoot --target=<container>

# Pod içinde tcpdump çalıştır
tcpdump -i eth0 -nn                          # Tüm trafik
tcpdump -i eth0 port 80 -nn                  # HTTP trafiği
tcpdump -i eth0 host 10.0.0.5 -nn           # Belirli IP
tcpdump -i eth0 -w /tmp/capture.pcap         # Dosyaya kaydet

# Yakalanan dosyayı dışarı çek
kubectl cp <pod>:/tmp/capture.pcap ./capture.pcap
# Wireshark ile analiz et
```

---

## kubectl events — Cluster Olayları

```bash
# Namespace olayları (zaman sırası)
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Sadece Warning olayları
kubectl get events -n <namespace> --field-selector type=Warning

# Belirli objeye ait olaylar
kubectl get events --field-selector involvedObject.name=<pod-adı>

# Tüm cluster olayları (dikkatli — çok fazla çıktı)
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Gerçek zamanlı olayları izle
kubectl get events -n <namespace> -w
```

---

## kubectl top — Kaynak Kullanımı

```bash
# Node kaynak kullanımı
kubectl top nodes
kubectl top nodes --sort-by=cpu
kubectl top nodes --sort-by=memory

# Pod kaynak kullanımı
kubectl top pods -n <namespace>
kubectl top pods -A --sort-by=memory | head -20
kubectl top pods --containers -n <namespace>    # Container bazında

# metrics-server kurulu değilse:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## Port-Forward — Servise Doğrudan Bağlan

```bash
# Pod'a doğrudan bağlan
kubectl port-forward pod/<pod> 8080:80

# Service üzerinden
kubectl port-forward svc/<servis> 8080:80 -n <namespace>

# Deployment üzerinden (herhangi bir pod'a)
kubectl port-forward deployment/<dep> 8080:80

# Arka planda çalıştır
kubectl port-forward svc/grafana 3000:80 -n monitoring &
```

---

## Stern / kubectl logs — Gelişmiş Log İzleme

```bash
# Çoklu pod log (label ile)
kubectl logs -l app=web-app -n production --tail=100 -f

# Önceki container'ın logları
kubectl logs <pod> --previous
kubectl logs <pod> -c <container> --previous

# Zaman bazlı log
kubectl logs <pod> --since=1h
kubectl logs <pod> --since-time="2026-04-25T18:00:00Z"

# stern (gelişmiş multi-pod log)
# https://github.com/stern/stern
stern web-app -n production                  # Label bazlı
stern "web-app-.*" -n production --tail 50   # Regex
stern . -n production --container nginx      # Belirli container
```

---

## kubectl diff & apply --dry-run

```bash
# Değişikliği apply etmeden önce ne değişecek gör
kubectl diff -f deployment.yaml

# Dry-run (gerçekte uygulamadan)
kubectl apply -f deployment.yaml --dry-run=client
kubectl apply -f deployment.yaml --dry-run=server   # API validation dahil

# Server-side validation (admission webhook kontrolü dahil)
kubectl create -f pod.yaml --dry-run=server
```

---

## RBAC Debug

```bash
# Belirli bir kullanıcının yetkisini sorgula
kubectl auth can-i create pods --as=system:serviceaccount:default:my-sa
kubectl auth can-i delete secrets -n production --as=developer

# Tüm izinleri listele
kubectl auth can-i --list --as=system:serviceaccount:default:my-sa

# ServiceAccount token'ını decode et
kubectl get secret <sa-token-secret> -o jsonpath='{.data.token}' | base64 -d | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

---

## Audit Log Analizi

```bash
# API Server audit log konumu (varsayılan)
cat /var/log/kubernetes/audit.log | jq '.' | head -50

# Belirli kaynak üzerindeki işlemler
cat /var/log/kubernetes/audit.log | jq 'select(.objectRef.resource=="secrets")' | tail -20

# Belirli kullanıcının işlemleri
cat /var/log/kubernetes/audit.log | jq 'select(.user.username=="admin")' | tail -20
```

---

## Hızlı Tanı Araç Seti

```bash
# Sağlık özeti (tek komut)
kubectl get nodes,pods -A | grep -v Running | grep -v Completed

# Tüm Warning event'ler
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20

# Yüksek kaynak tüketen pod'lar
kubectl top pods -A --sort-by=cpu | head -10

# Pending pod'lar
kubectl get pods -A --field-selector status.phase=Pending

# CrashLoop pod'lar
kubectl get pods -A | grep CrashLoopBackOff

# Başarısız pod'lar
kubectl get pods -A | grep -E "Error|OOMKilled|ImagePull"

# Node durumu
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,MEMORY:.status.allocatable.memory,CPU:.status.allocatable.cpu'
```

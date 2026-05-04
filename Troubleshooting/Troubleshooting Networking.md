# Troubleshooting: Networking

Kubernetes ağ sorunları sinsi olabilir — pod çalışıyor ama bağlanamıyor, servis var ama erişilemiyor, DNS çalışmıyor. Bu bölüm katman katman tanı yapar.

---

## Ağ Katmanları (Nereden Başlayacağını Bil)

```
[İnternet]
     │
[LoadBalancer / NodePort]
     │
[Ingress Controller]
     │
[Service (kube-proxy / eBPF)]
     │
[Pod → Container]
     │
[CNI Plugin (Cilium/Flannel/Calico)]
     │
[Linux Kernel (iptables / eBPF)]
```

Sorun hangi katmanda? Yukarıdan aşağı doğru test ederek daralt.

---

## DNS Sorunları

### Teşhis
```bash
# Pod içinden DNS testi
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# CoreDNS pod'larının durumu
kubectl get pods -n kube-system -l k8s-app=kube-dns

# CoreDNS logları
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Pod içinden servis adını çöz
kubectl exec -it <pod> -- nslookup <servis-adı>.<namespace>.svc.cluster.local
kubectl exec -it <pod> -- cat /etc/resolv.conf
```

### Yaygın DNS Sorunları

```bash
# 1. CoreDNS pod çalışmıyor
kubectl describe pod -n kube-system coredns-<hash>
# Genellikle: ConfigMap hatası veya upstream DNS erişim sorunu

# 2. Yanlış namespace ile servis adı
# YANLIŞ: nslookup my-service (farklı namespace'deyse)
# DOĞRU:  nslookup my-service.production.svc.cluster.local

# 3. ndots ayarı — kısa isimlerin çözümlenmesi
# /etc/resolv.conf içindeki "ndots:5" ayarı
# Kısa isim denemeden önce cluster.local suffix ekler
# Çözüm: FQDN kullan (nokta ile biter): my-service.production.svc.cluster.local.

# 4. Host DNS leak (pod dnsPolicy)
spec:
  dnsPolicy: ClusterFirst        # Default — cluster DNS kullan
  # dnsPolicy: Default          # Node'un DNS'ini kullan (cluster DNS yok)
  # dnsPolicy: None             # dnsConfig ile manuel tanımla
```

---

## Service Erişim Sorunları

### Pod → Service Bağlantısı Test

```bash
# 1. Service mevcut mu?
kubectl get svc -n <namespace>

# 2. Service'in endpoint'leri var mı? (Pod seçiliyor mu?)
kubectl get endpoints <servis-adı> -n <namespace>
# Boşsa: selector etiketleri pod etiketleriyle eşleşmiyor

# 3. Label selector kontrolü
kubectl get svc <servis> -o jsonpath='{.spec.selector}'
kubectl get pods -n <namespace> --show-labels
# Yukarıdaki etiketler eşleşmeli

# 4. Port numaraları doğru mu?
kubectl describe svc <servis>
# Port: 80/TCP → targetPort: 8080/TCP
# Container gerçekten 8080'de mi dinliyor?
kubectl exec <pod> -- netstat -tlnp   # veya ss -tlnp

# 5. Doğrudan pod IP'ye eriş (service bypass)
POD_IP=$(kubectl get pod <pod> -o jsonpath='{.status.podIP}')
kubectl run test --image=busybox --rm -it --restart=Never -- wget -O- http://$POD_IP:8080
```

### ClusterIP → NodePort → LoadBalancer

```bash
# ClusterIP testi (cluster içinden)
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://<servis-adı>.<namespace>.svc.cluster.local:<port>

# NodePort testi (dışarıdan)
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[0].address}')
NODE_PORT=$(kubectl get svc <servis> -o jsonpath='{.spec.ports[0].nodePort}')
curl http://$NODE_IP:$NODE_PORT

# LoadBalancer EXTERNAL-IP <pending> kalıyorsa
kubectl describe svc <servis>
# Cloud provider controller çalışıyor mu?
# Bare-metal'de MetalLB kurulu mu?
```

---

## Ingress Sorunları

```bash
# 1. Ingress controller pod çalışıyor mu?
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx <ingress-controller-pod>

# 2. Ingress kuralları doğru mu?
kubectl describe ingress <ingress-adı> -n <namespace>

# 3. Ingress class kontrolü
kubectl get ingressclass
# Ingress'te annotations veya ingressClassName doğru mu?
# annotations: kubernetes.io/ingress.class: "nginx"
# veya spec.ingressClassName: nginx

# 4. TLS/SSL sorunları
kubectl get certificate -n <namespace>      # cert-manager
kubectl describe certificate <cert>
kubectl get secret <tls-secret> -n <namespace>

# 5. Path eşleşme testi
curl -v http://<host>/api/v1/users
# Ingress path: /api(/|$)(.*) → nginx regex gerektiriyor mu?
```

---

## CNI / Pod-to-Pod Bağlantı Sorunları

```bash
# İki pod arasında bağlantı testi
kubectl run sender --image=busybox --rm -it --restart=Never -- \
  ping <hedef-pod-IP>

# Pod IP'leri öğren
kubectl get pods -o wide -n <namespace>

# Node'lar arası iletişim (CNI tüneli)
# Cilium kullanıyorsanız:
cilium connectivity test

# Cilium pod durumu
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl exec -n kube-system <cilium-pod> -- cilium status

# Flannel / Calico
kubectl get pods -n kube-system | grep -E "flannel|calico"
```

---

## NetworkPolicy Blokları

### "Bağlanamıyorum ama servis/pod doğru görünüyor"

```bash
# Namespace'te NetworkPolicy var mı?
kubectl get networkpolicy -n <namespace>

# Hangi policy'ler uygulanıyor?
kubectl describe networkpolicy -n <namespace>

# Policy bypass testi — geçici olarak sil (TEST ortamında!)
kubectl delete networkpolicy <policy> -n <namespace>
# Bağlantı düzeldiyse policy çok kısıtlayıcı demektir
```

```yaml
# En sık görülen hata: Default-deny + eksik ingress kuralı
# Bu policy tüm giriş trafiğini keser:
kind: NetworkPolicy
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  # ingress: [] → boş = hiçbir şeye izin yok!

# Düzeltme — belirli namespace'den izin ver:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
```

---

## kube-proxy Sorunları

```bash
# kube-proxy durumu
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system <kube-proxy-pod>

# iptables kuralları oluşturulmuş mu?
# Node üzerinde:
iptables -t nat -L KUBE-SERVICES | grep <servis-adı>

# Cilium'da eBPF ile kube-proxy değiştirilmişse:
kubectl exec -n kube-system <cilium-pod> -- cilium service list
```

---

## Genel Ağ Tanı Akışı

```
Bağlantı sorunu
     │
     ├── Pod çalışıyor mu? → kubectl get pods
     │
     ├── DNS çözümleniyor mu? → nslookup servis-adı
     │         └── Hayır → CoreDNS logları
     │
     ├── Endpoint var mı? → kubectl get endpoints
     │         └── Boş → Label selector hatası
     │
     ├── Doğrudan Pod IP'ye bağlanıyor mu?
     │         └── Hayır → CNI sorunu
     │
     ├── Service IP'ye bağlanıyor mu?
     │         └── Hayır → kube-proxy / eBPF sorunu
     │
     ├── Ingress'ten geçiyor mu?
     │         └── Hayır → Ingress controller / TLS sorunu
     │
     └── Her şey tamam ama yine de yok → NetworkPolicy kontrolü
```

# Cluster Hardening ve Security Audit

Bu bölümde cluster'ınızı gerçek dünya saldırılarına karşı nasıl sertleştireceğinizi (hardening) öğreneceğiz.

## 5.1 CIS Benchmark ile Denetim

Center for Internet Security (CIS), Kubernetes için yüzlerce maddelik bir güvenlik kontrol listesi sunar.

```bash
# kube-bench ile CIS denetimi
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# Sonuçları gör
kubectl logs job.batch/kube-bench

# Sadece başarısız testler
kubectl logs job.batch/kube-bench | grep -E 'FAIL|WARN'
```

## 5.2 API Server Hardening

```yaml
# kubeadm yapılandırması
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  extraArgs:
    anonymous-auth: "false"                    # Anonim erişim kapat
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-log-maxage: "30"
    audit-log-maxbackup: "10"
    audit-log-maxsize: "100"
    enable-admission-plugins: "NodeRestriction,AlwaysPullImages"
    encryption-provider-config: "/etc/kubernetes/encryption-config.yaml"
```

### etcd Åifreleme

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <BASE64_32_BYTE_KEY>
  - identity: {}   # Fallback (şifresiz okuma için)
```

## 5.3 Node ve Konteyner Hardening

Her pod için zorunlu hale getirilmesi gereken `securityContext`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true               # Root dışı kullanıcı
        seccompProfile:
          type: RuntimeDefault           # Sistem çağrısı filtresi
      containers:
      - name: app
        image: my-app:v1.0.0
        securityContext:
          runAsUser: 1000                # Belirli kullanıcı ID
          runAsGroup: 3000
          readOnlyRootFilesystem: true   # Dosya sistemi sadece okunabilir
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL                        # Tüm Linux yeteneklerini kaldır
            add:
            - NET_BIND_SERVICE           # Sadece gerekli olanı ekle
```

## 5.4 Temel Hardening Adımları

### Node Güvenliği
```bash
# SSH sadece jump-host üzerinden
# /etc/ssh/sshd_config
PasswordAuthentication no
AllowUsers admin
AllowGroups sre-team
```

### etcd Güvenliği

```bash
# etcd sadece localhost ve TLS ile dinlemelidir
# etcd flags:
--listen-client-urls=https://127.0.0.1:2379
--advertise-client-urls=https://127.0.0.1:2379
--cert-file=/etc/kubernetes/pki/etcd/server.crt
--key-file=/etc/kubernetes/pki/etcd/server.key
--peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
--client-cert-auth=true
```

### Kontrol Listesi

```bash
# 1. Anonymous auth kapalı mı?
curl -k https://<API_SERVER>:6443/api --header "Authorization: Bearer bad-token"
# 401 dönmeli

# 2. etcd dışarıya açık mı? (boş dönmeli)
nmap -p 2379 <NODE_IP>

# 3. Pod'lar root mu çalışıyor?
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].securityContext.runAsUser}{"\n"}{end}'

# 4. Privileged pod var mı?
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].securityContext.privileged}{"\n"}{end}'
```

## 5.5 Trivy ile Cluster Denetimi

```bash
# Tam cluster güvenlik raporu
trivy k8s --report summary cluster

# Sadece yüksek/kritik açıklar
trivy k8s --severity HIGH,CRITICAL --report all cluster
```

> [!CAUTION]
> Cluster hardening adımlarını production'a uygulamadan önce mutlaka test ortamında deneyin. `--anonymous-auth=false` veya yanlış audit policy bazı sistem bileşenlerini kırabilir.


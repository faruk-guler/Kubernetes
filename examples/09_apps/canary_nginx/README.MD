# NGINX Ingress ile Canary Deployment Örnekleri

Bu dizin, standart Kubernetes NGINX Ingress controller kullanılarak nasıl Canary Deployment yapılabileceğine dair temel YAML şablonlarını içerir. Eski yöntem `Service` parçalama pratiğine veya Argo Rollouts'a kıyasla "Ağırlıklı Trafik Yönlendirme" (Traffic Weighting) özelliğini doğrudan Ingress üzerinden yönetmeyi sağlar.

**Önemli Annotation'lar:**
- `nginx.ingress.kubernetes.io/canary: "true"`
- `nginx.ingress.kubernetes.io/canary-weight: "30"`

*(Bootcamp kütüphanesinden entegre edilmiştir.)*

---

### Trafik Yönlendirmesini Test Etme Komutları (Grep)

```bash
for i in $(seq 1 10); do curl -s --resolve canary.echo.pod.name.com:80:<Ingress-Controller-IP> canary.echo.pod.name.com; done
```
```bash
for i in $(seq 1 10); do curl -s --resolve canary.devopslearnwith.us:80:146.190.204.67 canary.devopslearnwith.us; done | grep -o '<span id='\''podName'\''>[^<]*' | sed 's/<[^>]*>//g'
```
```bash
watch curl canary.devopslearnwith.us
```
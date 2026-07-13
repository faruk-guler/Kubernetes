# Konteyner İmaj Hazırlama ve Kayıt Defteri Yönetimi (Container Runtime & Registry)

İyi bir geliştirici, hazırladığı uygulamayı sunucuda çalıştırmadan önce steril, taşınması kolay ve güvenli bir kaba (konteyner imajı) koyar. Hazırlanan bu imajlar, merkezi kilitli antrepolara (**Container Registry**) yüklenir. Kubernetes, bu antrepolardan sadece yetki anahtarı (**imagePullSecrets**) olanların konteynerleri çekip sunuculara dağıtmasına izin verir.

Eğer bu imajların üzerinde koştuğu ana makineleri (sanal sunucuları) de standartlaştırmak istersek, adeta bir kalıp döküm makinesi gibi çalışan **HashiCorp Packer** ile altın imajlar (**Golden Image**) üretiriz.

Bu bölümde imaj hazırlamanın, güvenli saklamanın, Buildah ile daemonless/rootless build işlemlerinin ve Harbor kurumsal registry entegrasyonunun detaylarını inceleyeceğiz.

---

## 1. HashiCorp Packer ile Altın İmaj (Golden Image) Oluşturma

Kubernetes düğümlerinin (nodes) üzerinde koştuğu işletim sistemi imajlarını (AMI, VMDK, ISO) otomatize etmek, sürümlerini sabitlemek ve standart güvenlik ayarlarını (kermel modülleri, sysctl) kurmak için Packer kullanılır:

```hcl
# k8s-node.pkr.hcl
source "amazon-ebs" "k8s" {
  ami_name      = "k8s-node-ubuntu-{{timestamp}}"
  instance_type = "t3.medium"
  region        = "eu-west-1"
  source_ami    = "ami-0123456789abcdef0" # Base Ubuntu AMI
  ssh_username  = "ubuntu"
}

build {
  sources = ["source.amazon-ebs.k8s"]

  provisioner "shell" {
    # Kubernetes kurulum script'ini düğüm üzerinde çalıştır
    script = "./scripts/install-k8s.sh"
  }
}
```

---

## 2. Containerfile ve Buildah ile Rootless İmaj Derleme

Geleneksel imaj derleme işlemlerinde arka planda çalışan bir `docker` daemon'ına ve `root` yetkisine ihtiyaç duyulur. Bu durum özellikle CI/CD sunucularında güvenlik açığı yaratır.

**Buildah**, bir docker daemon'ına (arkaplan servisine) gerek duymadan, root yetkileri olmadan (rootless) imaj derlememizi sağlayan OCI uyumlu bir araçtır. Buildah ekosisteminde `Dockerfile` yerine genellikle **`Containerfile`** ismi tercih edilir.

### Buildah ile Adım Adım İmaj Derleme (Bash)

```bash
# 1. Base imajdan geçici bir konteyner oluştur
ctr=$(buildah from nginx:alpine)

# 2. Konteyner içinde komut çalıştır (curl paketini yükle)
buildah run $ctr -- apk add --no-cache curl

# 3. İmaja etiket (label) ekle
buildah config --label version=1.0 --label maintainer="devops" $ctr

# 4. Değişiklikleri yeni bir imaj olarak kaydet
buildah commit $ctr my-custom-nginx:v1.0

# 5. İmajı registry'ye gönder
buildah push my-custom-nginx:v1.0 docker://registry.example.com/my-custom-nginx:v1.0

# 6. Geçici konteyneri temizle
buildah rm $ctr
```

---

## 3. Harbor — Kurumsal İmaj Kayıt Defteri (Enterprise Container Registry)

**Harbor**, imajlarınızı kendi veri merkezinizde (on-premise) saklamanızı sağlayan, rol tabanlı erişim kontrolü (RBAC), zafiyet taraması (Trivy entegreli) ve imza doğrulama (Cosign) sunan CNCF Graduated statüsünde kurumsal bir kayıt defteridir.

### Harbor Kurulumu (Helm)

```bash
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor \
  --namespace harbor \
  --create-namespace \
  --set expose.type=ingress \
  --set expose.tls.enabled=true \
  --set harborAdminPassword=HarborGuvenliSifre123 \
  --set persistence.persistentVolumeClaim.registry.storageClass=longhorn
```

### Harbor'a İmaj Yükleme (Push) Adımları

```bash
# 1. Harbor sunucusuna giriş yapın
docker login registry.example.com -u admin -p HarborGuvenliSifre123

# 2. İmajı Harbor projelerinize göre etiketleyin
docker tag myapp:v1.0 registry.example.com/production/myapp:v1.0

# 3. İmajı Harbor'a push edin
docker push registry.example.com/production/myapp:v1.0
```

---

## 4. Kubernetes Üzerinde `imagePullSecrets` Tanımlama

Eğer imajlarınız Harbor, Docker Hub Private veya GHCR gibi özel (kimlik doğrulaması gerektiren) bir registry'de duruyorsa, Kubernetes podlarının bu imajları çekebilmesi için kimlik bilgisi (credential) içeren bir Secret oluşturulmalıdır:

```bash
kubectl create secret docker-registry registry-credentials \
  --docker-server=registry.example.com \
  --docker-username=admin \
  --docker-password=HarborGuvenliSifre123 \
  --docker-email=admin@example.com \
  -n production
```

Bu secret, pod tanımı altında `imagePullSecrets` parametresine bağlanır:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [konteyner_calisma_zamani_ve_kayit_defteri_manifest_1.yaml](../Manifests/02_containers/konteyner_calisma_zamani_ve_kayit_defteri_manifest_1.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## 5. CI/CD Entegrasyonu ile Otomatik Zafiyet Taraması

İmajları derleyip registry'ye göndermeden önce CI/CD hattı üzerinde otomatik güvenlik taraması yapmak en iyi pratikler arasındadır. GitHub Actions üzerinde Trivy adımı şu şekilde kurgulanabilir:

📌 **Örnek Manifest:** Okunabilirliği korumak amacıyla uzun YAML dosyası ayrılmıştır. İlgili konfigürasyonun tam halini [konteyner_calisma_zamani_ve_kayit_defteri_manifest_2.yaml](../Manifests/02_containers/konteyner_calisma_zamani_ve_kayit_defteri_manifest_2.yaml) adresinden inceleyebilir veya doğrudan kümenize uygulayabilirsiniz.

---

## Özet

Konteyner imajlarının üretimi ve saklanması, altyapı güvenliğinin kapısıdır. **Buildah** ile rootless derleme yapmak, **Harbor** ile imajları zafiyet taramasından geçirerek on-premise saklamak ve Kubernetes'te **`imagePullSecrets`** ile yetkisiz erişimleri engellemek kurumsal standartların temelini oluşturur.

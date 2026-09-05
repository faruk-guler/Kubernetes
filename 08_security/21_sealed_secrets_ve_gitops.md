# Bitnami Sealed Secrets: GitOps ile Şifrelerin Güvenli Yönetimi

GitOps yaklaşımının ("Her şey Git'te tanımlı olsun") en büyük ikilemi gizli bilgilerdir (**Kubernetes Secret**).
Kubernetes'teki varsayılan `Secret` nesneleri şifrelenmiş (encrypted) değil, yalnızca **Base64** ile kodlanmıştır. `echo -n "c2VjcmV0" | base64 -d` komutunu çalıştıran herkes parolayı anında okuyabilir. Bu nedenle standart Secret YAML dosyalarını Git'e push etmek affedilemez bir güvenlik açığıdır.

Harici bir HashiCorp Vault veya AWS Secrets Manager sunucusu kurmadan, şifreleri doğrudan Git deponuzda güvenle saklamanın en pratik ve popüler yolu **Bitnami Sealed Secrets** aracıdır.

---

## 1. Sealed Secrets Nasıl Çalışır? (Asimetrik Kriptografi)

Sealed Secrets, açık anahtarlı (asimetrik) şifreleme mantığıyla çalışır:

1. **Küme İçi Denetleyici (Controller):** Kümeye kurulduğunda otomatik olarak bir çift asimetrik anahtar üretir:
   - **Genel Anahtar (Public Key):** Dünyaya açıktır. Herkes şifreleme yapmak için kullanabilir.
   - **Özel Anahtar (Private Key):** Sadece küme içindeki controller pod'unda saklanır. Şifreyi yalnızca bu anahtar çözebilir.
2. **Geliştirici Tarafı (`kubeseal` CLI):** Geliştirici, bilgisayarındaki hassas YAML dosyasını genel anahtarı kullanarak şifreler ve ortaya bir `SealedSecret` nesnesi çıkar.
3. **Git'e Push:** Bu `SealedSecret` dosyası artık güvenle GitHub / GitLab deponuza commit edilebilir. Çünkü özel anahtar olmadan hiç kimse (GitHub dahil) şifreyi çözemez.
4. **Çözülme:** ArgoCD veya Flux bu dosyayı kümeye uyguladığında, kümedeki Sealed Secrets Controller dosyayı yakalar, özel anahtarıyla çözer ve aynı namespace'te standart bir Kubernetes `Secret` nesnesine dönüştürür.

```text
 [ Geliştirici ]
       │  (Standart Secret YAML)
       ▼
 [ kubeseal ] ─── (Public Key ile Şifrele)
       │
       ▼
 [ SealedSecret YAML ] ───► Git'e Push Et (Güvenli!)
                                  │
                                  ▼ (GitOps - ArgoCD / Flux)
 [ Kubernetes Kümesi ] ◄──────────┘
       │
       ▼
 [ Sealed Secrets Controller ] ─── (Private Key ile Çöz)
       │
       ▼
 [ Standart K8s Secret ] ───► Pod'lar Tarafından Tüketilir
```

---

## 2. Kurulum

### A. Küme İçi Controller Kurulumu

```bash
# En güncel sürümü resmi kaynaktan uygulayın
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml
```

Controller'ın ayağa kalktığını doğrulayın:

```bash
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

### B. İstemci (`kubeseal`) CLI Kurulumu

Bilgisayarınızda şifreleme yapacak olan CLI aracını yükleyin:

- **macOS (Homebrew):** `brew install kubeseal`
- **Linux:**

  ```bash
  wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz
  tar -xvzf kubeseal-0.26.0-linux-amd64.tar.gz
  sudo install -m 755 kubeseal /usr/local/bin/kubeseal
  ```

- **Windows:** `winget install Bitnami.Kubeseal` veya `scoop install kubeseal`

---

## 3. Adım Adım Şifreleme (Uygulama)

Diyelim ki üretim ortamında bir veritabanı şifresi tanımlamak istiyorsunuz:

### Adım 1: Standart bir Secret YAML hazırlayın (Asla Git'e atmayın!)

```bash
kubectl create secret generic db-credentials \
  --from-literal=username=dbadmin \
  --from-literal=password='CokGizliSifre123!' \
  --namespace production \
  --dry-run=client -o yaml > plain-secret.yaml
```

### Adım 2: `kubeseal` ile şifreleyin

```bash
kubeseal -f plain-secret.yaml -w sealed-secret.yaml --controller-namespace kube-system
```

Oluşan `sealed-secret.yaml` dosyası şuna benzer:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  encryptedData:
    password: AgBy1x89Fq...devasa_kriptolu_metin...
    username: AgBy1x89Fq...devasa_kriptolu_metin...
  template:
    metadata:
      name: db-credentials
      namespace: production
```

### Adım 3: Temizlik ve Git'e Gönderme

Artık ham şifrenin olduğu `plain-secret.yaml` dosyasını bilgisayarınızdan silebilirsiniz (`rm plain-secret.yaml`).
Oluşan `sealed-secret.yaml` dosyasını güvenle Git'e push edebilirsiniz!

---

## 4. Kapsam (Scope) Türleri: Güvenlik Sınırları

`kubeseal`, şifrelenen verinin çalınıp başka bir isim alanında veya başka bir isimle çözülmesini engellemek için üç farklı güvenlik kapsamı (**Scope**) sunar:

1. **Strict (Varsayılan - En Güvenli):** Şifrelenen gizli bilgi, **yalnızca** şifrelendiği `namespace` ve nesne `adı` (secret name) ile çözülebilir. Başka bir namespace'e kopyalansa bile çözülemez.
2. **Namespace-wide:** Şifrelenen bilgi, o `namespace` içindeki herhangi bir isimde çözülebilir. (`--scope namespace-wide`)
3. **Cluster-wide:** Şifrelenen bilgi kümedeki herhangi bir namespace veya isimde çözülebilir. Çok nadir, küme geneli paylaşılan wildcard sertifikalar için kullanılır. (`--scope cluster-wide`)

---

## 5. Hayat Kurtaran SRE Pratiği: Anahtarın Yedeklenmesi

Sealed Secrets Controller'ın ürettiği özel anahtar (Private Key) `kube-system` isim alanında bir Kubernetes Secret'ı olarak saklanır.

> **[WARNING] Felaket Kurtarma Uyarısı:** Eğer kümeniz tamamen çökerse ve bu Secret'ı yedeklemediyseniz, Git'te duran yüzlerce `SealedSecret` dosyanız **sonsuza kadar kilitli kalır ve bir daha asla çözülemez!**

Özel anahtarı güvenli ve şifreli bir ortama (örneğin kurumsal KeePass veya 1Password kasasına) yedekleyin:

```bash
# 1. Controller'ın aktif şifreleme anahtarını dışarı aktarın
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > master-sealed-secrets-key.yaml
```

Yeni bir küme kurduğunuzda, Sealed Secrets Controller'ı ayağa kaldırmadan **önce** bu anahtarı kümeye uygularsanız, Git'teki tüm eski SealedSecret'larınız anında yeni kümede de tıkır tıkır çözülmeye başlar:

```bash
kubectl apply -f master-sealed-secrets-key.yaml
```

---

## 6. Sealed Secrets vs. External Secrets Operator (ESO)

| Karşılaştırma Kriteri | Bitnami Sealed Secrets | External Secrets Operator (ESO) |
| :--- | :--- | :--- |
| **Dış Bağımlılık** | Yok (Tamamen self-contained) | Var (Vault, AWS Secrets Manager, GCP SM) |
| **Şifre Saklama Yeri** | Kriptolu olarak doğrudan Git'te | Dış bir kasada (Vault / Cloud KMS) |
| **Yönetim Kolaylığı** | Çok Yüksek (Kur ve unut) | Orta (Dış kasa yetkilendirmesi gerekir) |
| **Dinamik Rotasyon** | Manuel (Yeniden kubeseal gerekir) | Otomatik (Kasadaki değişim kümeye anında yansır) |

## Özet

Eğer altyapınızda halihazırda kurulmuş bir HashiCorp Vault veya bulut sağlayıcınızın KMS servisi yoksa, GitOps yolculuğunda şifre güvenliğini sağlamanın en hızlı, en hafif ve en güvenilir yolu **Bitnami Sealed Secrets**'tır.

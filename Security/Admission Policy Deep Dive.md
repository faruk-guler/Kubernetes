```bash

kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.10.3/install.yaml

```
# Validation

Do�Yrulama politikaları, Kubernetes kaynaklarını yaratma veya güncelleme sırasında uygulanır. Bu politikalar, kaynakların belirli kurallara ve standartlara uygun olup olmadı�Yını kontrol eder. E�Yer bir kaynak, belirli bir do�Yrulama politikasına uymazsa, bu kayna�Yın olu�Yturulması veya güncellenmesi reddedilir.

�-rnek: Pod'ların sadece belirli imaj depolarından imaj çekmesini zorunlu kılmak için bir do�Yrulama politikası olu�Yturabilirsiniz.

```yaml
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: restrict-image-sources
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-image-source
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Images must be pulled from your-allowed-registry.com"
      pattern:
        spec:
          containers:
          - image: "your-allowed-registry.com/*"
```

### Politika Açıklaması:

1. `kind: ClusterPolicy`: Bu politika bir `ClusterPolicy` türündedir, yani tüm cluster'da uygulanır.
2. `name: restrict-image-sources`: Politikanın adı.
3. `validationFailureAction: enforce`: Bu politika zorlayıcı (enforcing) modda çalı�Yır, yani kurala uymayan Pod'lar reddedilir.
4. `match.resources.kinds: - Pod`: Bu politika sadece `Pod` türündeki kaynaklara uygulanır.
5. `validate.message`: Kurala uymayan kaynaklar için gösterilecek hata mesajı.
6. `pattern.spec.containers.image`: Pod tanımında bulunan her bir container'ın `image` alanı için beklenen patern. Bu örnekte, `your-allowed-registry.com/` ile ba�Ylayan imaj adlarına izin verilir.


* �-rnek-2: her olu�Yturulan podta `team` anahtarını içeren bir etiket olmasını bekler. 

```bash
kubectl create -f- << EOF
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-team
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "label 'team' is required"
      pattern:
        metadata:
          labels:
            team: "?*"
EOF

```

* Test
```bash
kubectl create deployment nginx --image=nginx


kubectl run nginx --image nginx --labels team=backend

kubectl get policyreport
```

* deny unkown repositories

```yaml

apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: allowed-repo
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-registries
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Registry not allowed"
      pattern:
        spec:
          containers:
          - image: "docker.io/* | quay.io/*"


```

* deny privileged pods

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: prevent-privileged-containers
      match:
        resources:
          kinds:
            - Pod
      validate:
        message: "Privileged containers are not allowed"
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(privileged): false
```


# Mutation

Mutasyon politikaları, kaynakların yaratılma veya güncelleme sırasında dinamik olarak de�Yi�Ytirilmesini sa�Ylar. Bu politikalar, kaynak tanımlarına otomatik olarak alanlar ekler, mevcut alanları de�Yi�Ytirir veya alanları kaldırır.

Kyverno'da `mutate` bölümü, Kubernetes kaynaklarını dinamik olarak de�Yi�Ytirmek için kullanılır. Bu, kaynak tanımlarına otomatik olarak alanlar eklemek, mevcut alanları de�Yi�Ytirmek veya alanları kaldırmak için kullanılır. Mutasyon için iki temel yöntem vardır: `patchStrategicMerge` ve `overlay`.

### 1. **patchStrategicMerge:**
`patchStrategicMerge` yöntemi, bir kaynak tanımına spesifik alanları eklemek veya de�Yi�Ytirmek için kullanılır. Bu yöntemle, belirli alanlara yapılan de�Yi�Yiklikler tanımlandı�Yı gibi uygulanır.

#### �-rnek:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-security-context
spec:
  rules:
  - name: patch-security-context
    match:
      resources:
        kinds:
        - Pod
    mutate:
      patchStrategicMerge:
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
```

Bu örnekte, Pod'lara `securityContext` eklenir ve `runAsNonRoot: true` ve `runAsUser: 1000` olarak ayarlanır.

### 2. **overlay:**
`overlay` yöntemi, bir kaynak üzerine daha geni�Y ve kapsamlı de�Yi�Yiklikler yapmak için kullanılır. `overlay` daha kompleks ve detaylı mutasyonlar için uygundur ve `patchStrategicMerge` ile benzer �Yekilde çalı�Yır ancak daha fazla seçenek sunar.

#### �-rnek:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-labels-and-annotations
spec:
  rules:
  - name: patch-labels-annotations
    match:
      resources:
        kinds:
        - Pod
    mutate:
      overlay:
        metadata:
          labels:
            my-label: my-label-value
          annotations:
            my-annotation: my-annotation-value
```

Bu örnekte, Pod'lara `my-label: my-label-value` etiketi ve `my-annotation: my-annotation-value` notu eklenir.

### Farklar:
- `patchStrategicMerge` daha basit ve spesifik alan de�Yi�Yiklikleri için uygundur.
- `overlay` daha kapsamlı ve detaylı mutasyonlar yapmak için kullanılır ve daha fazla esneklik sunar.

Her iki yöntem de benzer amaçlar için kullanılabilir, ve hangi yöntemin kullanılaca�Yı spesifik kullanım durumunuza ve ihtiyacınıza ba�Ylıdır. Genellikle, daha basit ve spesifik mutasyonlar için `patchStrategicMerge`, daha kapsamlı ve detaylı mutasyonlar için `overlay` kullanılır.



Pod tanımlarına otomatik olarak bir güvenlik politikası eklemek için kullanabilece�Yiniz bir Kyverno mutasyon politikası örne�Yi bulunmaktadır. Bu örnekte, her Pod'a otomatik olarak bir `securityContext` eklenmektedir.

```yaml
apiVersion: kyverno.io/v1
kind: Policy
metadata:
  name: add-security-context
spec:
  rules:
    - name: add-securityContext
      match:
        resources:
          kinds:
          - Pod
      mutate:
        overlay:
          spec:
            securityContext:
              runAsNonRoot: true
              runAsUser: 1000
```

### Politika Açıklaması:

1. `kind: ClusterPolicy`: Bu politika bir `ClusterPolicy` türündedir, yani tüm cluster'da uygulanır.
2. `name: add-security-context`: Politikanın adı.
3. `match.resources.kinds: - Pod`: Bu politika sadece `Pod` türündeki kaynaklara uygulanır.
4. `mutate.overlay.spec.securityContext`: Mutasyon i�Ylemi sırasında Pod'a eklenecek `securityContext` tanımlanmı�Ytır. Bu örnekte, her Pod'un `runAsNonRoot: true` ve `runAsUser: 1000` olarak ayarlanacak bir `securityContext` alması sa�Ylanmaktadır.


Burada `team: bravo` �Yeklinde anahtar-de�Yerli bir etiket eklenmektedir. 

```bash
kubectl create -f- << EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-labels
spec:
  rules:
  - name: add-team
    match:
      any:
      - resources:
          kinds:
          - Pod
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            +(team): bravo
EOF

kubectl run redis --image redis

kubectl get pod redis --show-labels

kubectl run newredis --image redis -l team=alpha

kubectl get pod myredis --show-labels

```

## Generation

�oretim politikaları, di�Yer Kubernetes kaynaklarının yaratılmasına veya silinmesine yanıt olarak otomatik olarak kaynaklar üretir. Bu, belirli bir kayna�Yın yaratılmasına veya silinmesine yanıt olarak ba�Yka kaynakların da dinamik olarak yönetilmesini sa�Ylar.

�-rnek: Her yeni Namespace için otomatik olarak bir Role veya RoleBinding olu�Yturmak üzere bir üretim politikası kullanabilirsiniz.

�-rnek Politika:

A�Ya�Yıda bir Validation politika örne�Yi bulunmaktadır:

```bash
kubectl -n default create secret docker-registry regcred \
  --docker-server=myinternalreg.corp.com \
  --docker-username=john.doe \
  --docker-password=Passw0rd123! \
  --docker-email=john.doe@corp.com

kubectl create -f- << EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: sync-secrets
spec:
  rules:
  - name: sync-image-pull-secret
    match:
      any:
      - resources:
          kinds:
          - Namespace
    generate:
      apiVersion: v1
      kind: Secret
      name: regcred
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      clone:
        namespace: default
        name: regcred
EOF


kubectl create ns mytestns


kubectl -n mytestns get secret

kubectl delete clusterpolicy sync-secrets

```

* Her yeni Namespace için otomatik olarak bir Role veya RoleBinding olu�Yturmak üzere bir üretim politikası kullanabilirsiniz.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: generate-role-and-rolebinding
spec:
  rules:
    - name: create-default-role
      match:
        resources:
          kinds:
          - Namespace
      generate:
        kind: Role
        name: default-role
        namespace: "{{request.object.metadata.name}}"
        data:
          rules:
            - apiGroups: [""]
              resources: ["pods"]
              verbs: ["get", "list"]
    - name: create-rolebinding-for-default-role
      match:
        resources:
          kinds:
          - Namespace
      generate:
        kind: RoleBinding
        name: default-role-binding
        namespace: "{{request.object.metadata.name}}"
        data:
          subjects:
            - kind: Group
              name: 'system:authenticated'
              apiGroup: 'rbac.authorization.k8s.io'
          roleRef:
            kind: Role
            name: default-role
            apiGroup: 'rbac.authorization.k8s.io'
```

### Politika Açıklaması:

- İki kural içeren bir `ClusterPolicy` olu�Yturulmu�Ytur: `create-default-role` ve `create-rolebinding-for-default-role`.
- Her iki kural da `Namespace` kaynak türüyle e�Yle�Yir, yani yeni bir `Namespace` olu�Yturuldu�Yunda tetiklenirler.
- `create-default-role` kuralı:
  - `generate` bölümü kullanarak bir `Role` olu�Yturur.
  - Bu `Role`, olu�Yturulan `Namespace` içinde `default-role` adını alır.
  - Olu�Yturulan `Role`'de `pods` kayna�Yı için `get` ve `list` yetkileri verilir.
- `create-rolebinding-for-default-role` kuralı:
  - Benzer �Yekilde, `generate` bölümü kullanarak bir `RoleBinding` olu�Yturur.
  - `RoleBinding`, olu�Yturulan `Namespace` içinde `default-role-binding` adını alır ve `default-role`'e ba�Ylanır.
  - `RoleBinding`, `system:authenticated` grubunu `default-role`'e ba�Ylar.

### Uygulama Adımları:

1. Yukarıdaki YAML kodunu bir dosyaya yapı�Ytırın, örne�Yin `generate-role-and-rolebinding.yaml` olarak adlandırabilirsiniz.
2. `kubectl apply -f generate-role-and-rolebinding.yaml` komutunu kullanarak politikayı uygulayın.
3. Bundan sonra, her yeni olu�Yturulan `Namespace` için otomatik olarak bir `Role` ve `RoleBinding` olu�Yturulacaktır.

### Not:
- Bu örnekteki `Role` ve `RoleBinding` tanımları örnek amaçlıdır; gerçek kullanım senaryonuza göre bu de�Yerleri de�Yi�Ytirmelisiniz.
- `generate` kuralı, mevcut kaynaklar üzerinde herhangi bir etkiye sahip de�Yildir; sadece yeni olu�Yturulan kaynaklara uygulanır.

# policy vs clusterpolicy
Biri namespace seviyesinde çalı�Yırken di�Yeri  tüm küme için çalı�Yır.

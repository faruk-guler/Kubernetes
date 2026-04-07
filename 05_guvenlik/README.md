# 📖 Bölüm 5: Güvenlik ve Politika Yönetimi

## 📄 Dosyalar

| Dosya | Konu |
|:---|:---|
| 01_rbac_ve_oidc.md | RBAC, ServiceAccount, OIDC kurumsal kimlik |
| 02_kyverno_politika.md | Kyverno ile Policy-as-Code, PSS |
| 03_admission_controllers.md | Webhook'lar, CEL ValidatingAdmissionPolicy |
| 04_runtime_guvenlik_falco.md | Falco ile runtime tehdit algılama, Trivy |
| 05_cluster_hardening.md | CIS Benchmark, etcd güvenliği, container hardening |
| 06_supply_chain_security.md | Tedarik Zinciri Güvenliği, Sigstore, Cosign, SBOM |
| 07_spiffe_spire_zero_trust.md | SPIFFE/SPIRE ve X.509 Kriptografik Sıfır Güven (Zero-Trust) Kimlik Yönetimi |
---

## 🛠️ Uygulama ve Örnekler

RBAC ve PodDisruptionBudget için merkezi örnekler dizinine göz atın:

- [🛡️ Güvenlik ve RBAC Örnekleri](../examples/06_security_rbac/)

---
*← Ana Sayfa*

## 🎯 Bu Bölümden Sonra

- Cluster içinde en az yetki prensibiyle (Least Privilege) RBAC kurgulayabileceksiniz
- Kyverno ile politika bazlı denetim yapabileceksiniz
- Runtime güvenliğini Falco ile izleyebileceksiniz

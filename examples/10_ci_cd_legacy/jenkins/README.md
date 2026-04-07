# Legacy CI/CD: Jenkins Pipeline Örnekleri

Modern Kubernetes projelerinde **GitOps (ArgoCD / Flux)** kullanımı bir standart haline gelmiş olsa da (bkz: `04_gitops_ve_yapilandirma`), geleneksel ortamlardan geçiş yapacak olanlar veya "Klasik CI/CD" mimarisini merak eden okuyucular için bu klasörde örnek Jenkinsfile'lar bulunmaktadır.

**Örnekler Hakkında:**
- `kosullu-jenkinsfile`: Gelişmiş aşamalı (Development/Staging/Production) ve parametrik if-else koşulları içeren deploy script'i.
- `parametre-Jenkinsfile`: Versiyon, Branch ve Environment değişkenleriyle çalışan temel CI akışı.

*(Tech Istanbul Bootcamp CI/CD araçlarından uyarlanmıştır.)*

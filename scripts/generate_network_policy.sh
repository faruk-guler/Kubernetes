#!/bin/bash
set -euo pipefail

# ==============================================================================
# SRE Script: generate_network_policy.sh
# Açıklama: Belirtilen bir Pod veya Deployment'ı analiz ederek onun etiketlerini,
#           dinlediği portları tespit eder ve "Sıfır Güven (Zero Trust)"
#           standartlarında sıkılaştırılmış bir NetworkPolicy YAML şablonu üretir.
# Kullanım: ./generate_network_policy.sh <namespace> <pod_ismi> [cikti_dosyasi]
# Örnek   : ./generate_network_policy.sh production web-api-74f885bc6b-xyz netpol.yaml
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ "$#" -lt 2 ]; then
    echo -e "${RED}[HATA] Eksik parametre!${NC}"
    echo "Kullanım: $0 <namespace> <pod_ismi> [cikti_dosyasi]"
    echo "Örnek   : $0 production payment-service-xyz ./payment-netpol.yaml"
    exit 1
fi

NAMESPACE="$1"
POD_NAME="$2"
OUTPUT_FILE="${3:-}"

echo -e "${BLUE}=== Akıllı NetworkPolicy Üretici ===${NC}"
echo -e "Namespace: ${YELLOW}${NAMESPACE}${NC}"
echo -e "Pod      : ${YELLOW}${POD_NAME}${NC}"
echo "----------------------------------------------------------------------"

# 1. Pod varlığını kontrol et
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}[HATA] '$POD_NAME' pod'u '$NAMESPACE' isim alanında bulunamadı.${NC}"
    exit 1
fi

# 2. Pod etiketlerini ve portlarını topla
echo "Pod konfigürasyonu analiz ediliyor..."
APP_LABEL=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app}')
if [ -z "$APP_LABEL" ]; then
    APP_LABEL=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}')
fi

if [ -z "$APP_LABEL" ]; then
    MATCH_LABEL="app: $POD_NAME"
    POLICY_NAME="${POD_NAME}-netpol"
else
    MATCH_LABEL="app: $APP_LABEL"
    POLICY_NAME="${APP_LABEL}-netpol"
fi

CONTAINER_PORTS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].ports[*].containerPort}')

# YAML içeriğini oluştur
YAML_OUTPUT=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${POLICY_NAME}
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      ${MATCH_LABEL}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Yalnızca aynı namespace içindeki istemcilerden veya Ingress Controller'dan gelen isteklere izin ver
    - from:
        - podSelector: {} # İsteğe bağlı: matchLabels ile sadece belirli podlara kısıtlayın
      ports:
EOF
)

# Portları ekle
if [ -n "$CONTAINER_PORTS" ]; then
    for port in $CONTAINER_PORTS; do
        YAML_OUTPUT+=$(cat <<EOF

        - protocol: TCP
          port: ${port}
EOF
)
    done
else
    YAML_OUTPUT+=$(cat <<EOF

        - protocol: TCP
          port: 8080 # Dinlenen port otomatik tespit edilemedi, lütfen güncelleyin
EOF
)
fi

YAML_OUTPUT+=$(cat <<EOF

  egress:
    # 1. Kubernetes CoreDNS sorgularına her zaman izin verilmelidir (UDP/TCP 53)
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # 2. Cluster içi izin verilen dış servisler (Veritabanı vb. için düzenleyin)
    # - to:
    #     - podSelector:
    #         matchLabels:
    #           app: postgres
    #   ports:
    #     - protocol: TCP
    #       port: 5432
EOF
)

echo "----------------------------------------------------------------------"
echo -e "${GREEN}[BAŞARILI] Sıfır Güven (Zero-Trust) NetworkPolicy üretildi:${NC}"
echo ""
echo "$YAML_OUTPUT"
echo ""

if [ -n "$OUTPUT_FILE" ]; then
    echo "$YAML_OUTPUT" > "$OUTPUT_FILE"
    echo -e "${GREEN}[BİLGİ] Manifesto dosyaya kaydedildi: ${OUTPUT_FILE}${NC}"
fi

#!/usr/bin/env bash
# ==============================================================================
# Script: create_developer_kubeconfig.sh
# Description: Yeni bir geliştirici için X.509 sertifikası üretir, K8s CSR ile
#              imzalatır, RoleBinding tanımlar ve bağımsız bir Kubeconfig dosyası üretir.
# Kullanımı: ./create_developer_kubeconfig.sh <kullanici-adi> [namespace] [rol]
# Örnek:     ./create_developer_kubeconfig.sh ahmet development edit
# ==============================================================================
set -euo pipefail

USER_NAME="${1:-}"
TARGET_NS="${2:-default}"
ROLE_NAME="${3:-edit}" # view, edit, admin veya kümedeki özel bir ClusterRole

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$USER_NAME" ]; then
    echo -e "${BOLD}Kullanım:${NC} $0 <kullanici-adi> [namespace] [rol]"
    echo "Örnek:    $0 can development edit"
    exit 1
fi

WORK_DIR="/tmp/k8s-user-${USER_NAME}"
OUTPUT_KUBECONFIG="kubeconfig-${USER_NAME}.yaml"
mkdir -p "$WORK_DIR"

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}    GELİŞTİRİCİ KUBECONFIG VE RBAC OTOMASYONU                   ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "Kullanıcı: ${BOLD}${USER_NAME}${NC} | Namespace: ${BOLD}${TARGET_NS}${NC} | Rol: ${BOLD}${ROLE_NAME}${NC}"
echo ""

# 1. Private Key ve CSR oluşturma
echo -e "${BOLD}1. Kullanıcı için Özel Anahtar (Private Key) ve CSR Üretiliyor...${NC}"
openssl genrsa -out "${WORK_DIR}/${USER_NAME}.key" 2048 2>/dev/null
openssl req -new -key "${WORK_DIR}/${USER_NAME}.key" \
  -out "${WORK_DIR}/${USER_NAME}.csr" \
  -subj "/CN=${USER_NAME}/O=developers" 2>/dev/null

CSR_BASE64=$(base64 < "${WORK_DIR}/${USER_NAME}.csr" | tr -d '\n\r')

# 2. Kubernetes CSR Nesnesi Gönderme
echo -e "${BOLD}2. Kubernetes API'ye CertificateSigningRequest Gönderiliyor...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}-access
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 2592000 # 30 gün geçerli
  usages:
  - client auth
EOF

# 3. CSR Onaylama (Approval)
echo -e "${BOLD}3. CSR Yönetici Olarak Onaylanıyor...${NC}"
kubectl certificate approve "${USER_NAME}-access"

# İmzalanmış sertifikayı çek
echo -e "${BOLD}4. İmzalanmış İstemci Sertifikası Alınıyor...${NC}"
sleep 2
CLIENT_CERT=$(kubectl get csr "${USER_NAME}-access" -o jsonpath='{.status.certificate}')
echo "$CLIENT_CERT" | base64 -d > "${WORK_DIR}/${USER_NAME}.crt"

# 4. Namespace ve RoleBinding Oluşturma
echo -e "${BOLD}5. Hedef Namespace ve RBAC RoleBinding Yapılandırılıyor...${NC}"
kubectl create namespace "$TARGET_NS" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USER_NAME}-${ROLE_NAME}-binding
  namespace: ${TARGET_NS}
subjects:
- kind: User
  name: ${USER_NAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: ${ROLE_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

# 5. Bağımsız Kubeconfig Üretimi
echo -e "${BOLD}6. Taşınabilir (Self-Contained) Kubeconfig Üretiliyor...${NC}"
CLUSTER_NAME=$(kubectl config current-context)
APISERVER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CLIENT_CERT_B64=$(base64 < "${WORK_DIR}/${USER_NAME}.crt" | tr -d '\n\r')
CLIENT_KEY_B64=$(base64 < "${WORK_DIR}/${USER_NAME}.key" | tr -d '\n\r')

cat <<EOF > "$OUTPUT_KUBECONFIG"
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${APISERVER_ENDPOINT}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${TARGET_NS}
    user: ${USER_NAME}
  name: ${USER_NAME}@${CLUSTER_NAME}
current-context: ${USER_NAME}@${CLUSTER_NAME}
users:
- name: ${USER_NAME}
  user:
    client-certificate-data: ${CLIENT_CERT_B64}
    client-key-data: ${CLIENT_KEY_B64}
EOF

# Temizlik
rm -rf "$WORK_DIR"
kubectl delete csr "${USER_NAME}-access" >/dev/null 2>&1 || true

echo ""
echo -e "${GREEN}✔ Başarılı! Geliştirici Kubeconfig dosyası üretildi: ${BOLD}${OUTPUT_KUBECONFIG}${NC}"
echo -e "Test Etmek İçin: ${YELLOW}kubectl --kubeconfig=${OUTPUT_KUBECONFIG} get pods${NC}"

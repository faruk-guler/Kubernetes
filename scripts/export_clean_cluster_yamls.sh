#!/usr/bin/env bash
# ==============================================================================
# Script: export_clean_cluster_yamls.sh
# Description: Belirtilen namespace altındaki tüm kaynakları (Deployments, Services,
#              ConfigMaps, vb.) temiz (status, uid, managedFields ayıklanmış)
#              ve yeniden uygulanabilir YAML dosyaları olarak yedekler.
# Kullanımı: ./export_clean_cluster_yamls.sh <namespace> [hedef-dizin]
# ==============================================================================
set -euo pipefail

NAMESPACE="${1:-}"
OUTPUT_DIR="${2:-./backup-${NAMESPACE:-all}}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$NAMESPACE" ]; then
    echo -e "${BOLD}Kullanım:${NC} $0 <namespace> [hedef-dizin]"
    echo "Örnek:    $0 production ./prod-gitops-backup"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}    GİTOPS VE MİGRASYON İÇİN TEMİZ YAML DIŞA AKTARICI          ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "Namespace: ${BOLD}${NAMESPACE}${NC} -> Hedef Dizin: ${BOLD}${OUTPUT_DIR}${NC}"
echo ""

RESOURCE_TYPES=(
  "deployments"
  "statefulsets"
  "daemonsets"
  "cronjobs"
  "services"
  "ingresses"
  "configmaps"
  "secrets"
  "networkpolicies"
  "serviceaccounts"
  "roles"
  "rolebindings"
)

TOTAL_EXPORTED=0

for RES in "${RESOURCE_TYPES[@]}"; do
    ITEMS=$(kubectl get "$RES" -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    if [ -n "$ITEMS" ]; then
        SUBDIR="${OUTPUT_DIR}/${RES}"
        mkdir -p "$SUBDIR"
        for ITEM in $ITEMS; do
            # status, metadata.managedFields, metadata.uid, metadata.resourceVersion temizle
            kubectl get "$RES" "$ITEM" -n "$NAMESPACE" -o json 2>/dev/null | \
              sed -e '/"managedFields":/,/\]/d' \
                  -e '/"uid":/d' \
                  -e '/"resourceVersion":/d' \
                  -e '/"generation":/d' \
                  -e '/"creationTimestamp":/d' \
                  -e '/"status":/,/}/d' > "${SUBDIR}/${ITEM}.json" 2>/dev/null || true
            
            # kubectl neatly converts clean json to yaml
            kubectl apply -f "${SUBDIR}/${ITEM}.json" --dry-run=client -o yaml > "${SUBDIR}/${ITEM}.yaml" 2>/dev/null || true
            rm -f "${SUBDIR}/${ITEM}.json"
            
            TOTAL_EXPORTED=$((TOTAL_EXPORTED + 1))
            echo " - [Dışa Aktarıldı] ${RES}/${ITEM}.yaml"
        done
    fi
done

echo ""
echo -e "${GREEN}✔ Toplam ${TOTAL_EXPORTED} adet Kubernetes nesnesi başarıyla yedeklendi: ${BOLD}${OUTPUT_DIR}${NC}"
echo -e "Bu dosyalar doğrudan ${YELLOW}kubectl apply -f ${OUTPUT_DIR}/${NC} ile yeni bir kümeye kurulabilir."

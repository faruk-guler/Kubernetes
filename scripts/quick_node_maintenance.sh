#!/usr/bin/env bash
# ==============================================================================
# Script: quick_node_maintenance.sh
# Description: Düğüm bakımı için güvenli cordon, drain ve uncordon işlemlerini yürütür.
# Kullanımı: ./quick_node_maintenance.sh <cordon|drain|uncordon> <node-name>
# ==============================================================================
set -euo pipefail

ACTION="${1:-}"
NODE_NAME="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$ACTION" ] || [ -z "$NODE_NAME" ]; then
    echo -e "${BOLD}Kullanım:${NC} $0 <cordon|drain|uncordon> <node-name>"
    echo ""
    echo "Komutlar:"
    echo "  cordon    : Düğümü yeni pod planlamasına kapatır."
    echo "  drain     : Podları diğer düğümlere güvenle tahliye eder (PDB kurallarına uyar)."
    echo "  uncordon  : Bakım sonrası düğümü tekrar aktif hale getirir."
    exit 1
fi

case "$ACTION" in
    cordon)
        echo -e "${YELLOW}Düğüm planlamaya kapatılıyor (cordon): ${NODE_NAME}...${NC}"
        kubectl cordon "$NODE_NAME"
        echo -e "${GREEN}✔ Düğüm başarıyla kapatıldı (SchedulingDisabled).${NC}"
        ;;
    drain)
        echo -e "${YELLOW}Düğüm üzerindeki podlar tahliye ediliyor (drain): ${NODE_NAME}...${NC}"
        kubectl drain "$NODE_NAME" \
          --ignore-daemonsets \
          --delete-emptydir-data \
          --force \
          --grace-period=60 \
          --timeout=300s
        echo -e "${GREEN}✔ Düğüm başarıyla tahliye edildi.${NC}"
        ;;
    uncordon)
        echo -e "${GREEN}Düğüm tekrar planlamaya açılıyor (uncordon): ${NODE_NAME}...${NC}"
        kubectl uncordon "$NODE_NAME"
        echo -e "${GREEN}✔ Düğüm tekrar aktif hale getirildi.${NC}"
        ;;
    *)
        echo -e "${RED}[HATA] Geçersiz işlem: '$ACTION'. Geçerli seçenekler: cordon, drain, uncordon.${NC}"
        exit 1
        ;;
esac

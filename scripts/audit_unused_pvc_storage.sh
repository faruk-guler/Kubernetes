#!/usr/bin/env bash
# ==============================================================================
# Script: audit_unused_pvc_storage.sh
# Description: Sahipsiz (hiçbir pod tarafından bağlanmamış) PVC'leri ve askıda
#              kalan Released/Failed kalıcı birimleri (PV) denetleyip maliyet tasarrufu sağlar.
# Kullanımı: ./audit_unused_pvc_storage.sh [namespace]
# ==============================================================================
set -euo pipefail

NAMESPACE="${1:---all-namespaces}"
NS_FLAG=""
if [ "$NAMESPACE" != "--all-namespaces" ]; then
    NS_FLAG="-n $NAMESPACE"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}     KUBERNETES KALICI DEPOLAMA (PV / PVC) DENETÇİSİ            ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "Kapsam: ${NAMESPACE}"
echo ""

# 1. Askıda Kalan (Pending) PVC Taraması
echo -e "${BOLD}1. Hazır Olamayan (Pending) PVC'ler Taranıyor...${NC}"
PENDING_PVCS=$(kubectl get pvc $NS_FLAG --no-headers 2>/dev/null | grep 'Pending' || true)

if [ -z "$PENDING_PVCS" ]; then
    echo -e "   ${GREEN}✔ 'Pending' durumunda takılan PVC yok.${NC}"
else
    echo -e "   ${RED}✖ DİKKAT! Karşılanamayan PVC'ler tespit edildi (StorageClass veya Kota sorunu):${NC}"
    echo "$PENDING_PVCS" | awk '{print "     - [" $1 "] " $2 " (StorageClass: " $6 ")"}'
fi
echo ""

# 2. Sahipsiz (Unattached / Orphaned) PVC Taraması
echo -e "${BOLD}2. Hiçbir Pod Tarafından Kullanılmayan (Sahipsiz) PVC'ler Taranıyor...${NC}"

# Aktif podların kullandığı PVC'lerin listesini al
ACTIVE_PVCS=$(kubectl get pods $NS_FLAG -o jsonpath='{range .items[*]}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}{end}' | sort -u | grep -v '^$' || true)

# Mevcut tüm Bound PVC'leri tara
ALL_PVCS=$(kubectl get pvc $NS_FLAG --no-headers 2>/dev/null | grep 'Bound' || true)

ORPHAN_COUNT=0
if [ -n "$ALL_PVCS" ]; then
    while IFS= read -r line; do
        if [ "$NAMESPACE" == "--all-namespaces" ]; then
            PVC_NS=$(echo "$line" | awk '{print $1}')
            PVC_NAME=$(echo "$line" | awk '{print $2}')
            PVC_SIZE=$(echo "$line" | awk '{print $4}')
        else
            PVC_NS="$NAMESPACE"
            PVC_NAME=$(echo "$line" | awk '{print $1}')
            PVC_SIZE=$(echo "$line" | awk '{print $3}')
        fi

        if ! echo "$ACTIVE_PVCS" | grep -qx "$PVC_NAME"; then
            echo -e "   ${YELLOW}⚠ Sahipsiz PVC: [${PVC_NS}] ${PVC_NAME} (Boyut: ${PVC_SIZE}) -> Aktif bir pod bağlanmamış!${NC}"
            ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
        fi
    done <<< "$ALL_PVCS"
fi

if [ "$ORPHAN_COUNT" -eq 0 ]; then
    echo -e "   ${GREEN}✔ Tüm PVC'ler aktif bir pod tarafından kullanılıyor. Depolama israfı yok.${NC}"
else
    echo -e "   ${YELLOW}Toplam ${ORPHAN_COUNT} adet kullanılmayan PVC bulundu. İhtiyaç yoksa silinerek bulut disk maliyeti düşürülebilir.${NC}"
fi
echo ""

# 3. Released veya Failed Durumundaki PV'ler (Cluster Geneli)
echo -e "${BOLD}3. Askıda Kalan / Sahipsiz PV'ler (Released / Failed):${NC}"
ORPHAN_PVS=$(kubectl get pv --no-headers 2>/dev/null | grep -E 'Released|Failed' || true)

if [ -z "$ORPHAN_PVS" ]; then
    echo -e "   ${GREEN}✔ Kümede askıda kalan (Released/Failed) PV bulunmuyor.${NC}"
else
    echo -e "   ${RED}✖ Temizlenmeyi bekleyen PV'ler:${NC}"
    echo "$ORPHAN_PVS" | awk '{print "     - " $1 " Durum: " $5 " (Kapasite: " $2 ")"}'
fi

echo ""
echo -e "${BOLD}Depolama Denetimi Tamamlandı.${NC}"

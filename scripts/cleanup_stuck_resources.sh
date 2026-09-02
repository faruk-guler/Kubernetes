#!/usr/bin/env bash
# ==============================================================================
# Script: cleanup_stuck_resources.sh
# Description: Terminating durumunda takılan podları ve Evicted podları temizler.
# Kullanımı: ./cleanup_stuck_resources.sh
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}1. Evicted ve Hatalı Podlar Temizleniyor...${NC}"
EVICTED_PODS=$(kubectl get pods --all-namespaces --no-headers | grep -E 'Evicted|Error' || true)

if [ -n "$EVICTED_PODS" ]; then
    echo "$EVICTED_PODS" | awk '{print "-n", $1, $2}' | xargs -L 1 kubectl delete pod --wait=false || true
    echo -e "   ${GREEN}✔ Evicted ve Error durumundaki podlar silindi.${NC}"
else
    echo -e "   ${GREEN}✔ Temizlenecek Evicted pod bulunamadı.${NC}"
fi
echo ""

echo -e "${BOLD}2. 'Terminating' Durumunda Kilitlenen Podlar Taranıyor...${NC}"
STUCK_PODS=$(kubectl get pods --all-namespaces --no-headers | grep 'Terminating' || true)

if [ -n "$STUCK_PODS" ]; then
    echo -e "   ${YELLOW}⚠ Takılan podlar zorla sonlandırılıyor ve finalizer'ları temizleniyor:${NC}"
    while IFS= read -r line; do
        NS=$(echo "$line" | awk '{print $1}')
        POD=$(echo "$line" | awk '{print $2}')
        echo "     - Temizleniyor: [$NS] $POD"
        kubectl delete pod "$POD" -n "$NS" --grace-period=0 --force 2>/dev/null || true
        kubectl patch pod "$POD" -n "$NS" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    done <<< "$STUCK_PODS"
    echo -e "   ${GREEN}✔ Kilitlenen tüm podlar temizlendi.${NC}"
else
    echo -e "   ${GREEN}✔ 'Terminating' durumunda kilitlenen hiçbir pod yok.${NC}"
fi
echo ""
echo -e "${BOLD}Temizlik Tamamlandı.${NC}"

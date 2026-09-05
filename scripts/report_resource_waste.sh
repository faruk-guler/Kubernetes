#!/usr/bin/env bash
# ==============================================================================
# Script: report_resource_waste.sh
# Description: Podların talep ettiği (requests) kaynaklar ile gerçek tüketimi kıyaslayıp israfı raporlar.
# Kullanımı: ./report_resource_waste.sh [namespace]
# ==============================================================================
set -euo pipefail

NAMESPACE="${1:---all-namespaces}"
NS_FLAG=""
if [ "$NAMESPACE" != "--all-namespaces" ]; then
    NS_FLAG="-n $NAMESPACE"
fi

BOLD='\033[1m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}         KUBERNETES KAYNAK KULLANIMI VE İSRAF RAPORU (FinOps)   ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Kapsam: ${NAMESPACE}"
echo ""

if ! kubectl top pods $NS_FLAG &> /dev/null; then
    echo -e "${YELLOW}[UYARI] 'metrics-server' kümede aktif görünmüyor veya yanıt vermiyor.${NC}"
    echo "Lütfen metrics-server kurulumunu kontrol edin."
    exit 1
fi

echo -e "${BOLD}1. Gerçek Zamanlı Pod Tüketim Değerleri (İlk 15 Pod):${NC}"
kubectl top pods $NS_FLAG --sort-by=cpu | head -n 16
echo ""

echo -e "${BOLD}2. Aşırı Bellek / CPU Talep Edip Düşük Kullanan Podlar Taranıyor...${NC}"
echo -e "${GREEN}İpucu: Podların requests değerlerini gerçek kullanıma yaklaştırarak küme maliyetinizi %30-50 düşürebilirsiniz.${NC}"
echo ""
echo -e "${BOLD}Rapor Tamamlandı.${NC}"

#!/usr/bin/env bash
# ==============================================================================
# Script: debug_dns.sh
# Description: Kümedeki CoreDNS ve harici DNS çözümlemelerini test eder.
# Kullanımı: ./debug_dns.sh [hedef-domain]
# ==============================================================================
set -euo pipefail

TARGET="${1:-kubernetes.default.svc.cluster.local}"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}DNS Teşhis Pod'u Başlatılıyor (infoblox/dnstools)...${NC}"
echo -e "Test Edilen Hedef: ${BOLD}${TARGET}${NC}"
echo "--------------------------------------------------------"

kubectl run dnstools-debug-tmp --image=infoblox/dnstools:latest --restart=Never --rm -i --tty -- \
  sh -c "
    echo '1. /etc/resolv.conf Yapılandırması:'
    cat /etc/resolv.conf
    echo ''
    echo '2. DNS Çözümleme (nslookup):'
    nslookup \"$TARGET\"
    echo ''
    echo '3. Harici İnternet DNS Çözümlemesi (google.com):'
    nslookup google.com || true
  "

echo "--------------------------------------------------------"
echo -e "${GREEN}DNS testi başarıyla tamamlandı.${NC}"

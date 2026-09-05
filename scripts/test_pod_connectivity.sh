#!/usr/bin/env bash
# ==============================================================================
# Script: test_pod_connectivity.sh
# Description: Küme içinden hedef bir servis veya IP'ye L4/L7 ağ ve DNS erişimini test eder.
# Kullanımı: ./test_pod_connectivity.sh <hedef-servis-veya-ip> [port]
# ==============================================================================
set -euo pipefail

TARGET="${1:-kubernetes.default.svc.cluster.local}"
PORT="${2:-443}"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}Geçici Hata Ayıklama Pod'u Başlatılıyor (curlimages/curl)...${NC}"
echo -e "Hedef: ${BOLD}${TARGET}:${PORT}${NC}"
echo "--------------------------------------------------------"

kubectl run net-debugger-tmp --image=curlimages/curl:8.10.1 --restart=Never --rm -i --tty -- \
  sh -c "
    echo '1. DNS Çözümleme Testi:'
    nslookup \"$TARGET\" || true
    echo ''
    echo '2. Port ve Bağlantı Testi (TCP Connect):'
    nc -z -v -w 3 \"$TARGET\" \"$PORT\" || true
    echo ''
    echo '3. HTTP/HTTPS İstek Testi (Latency ve Yanıt Kodu):'
    curl -k -s -o /dev/null -w 'HTTP Kod: %{http_code}\nDNS Çözümleme: %{time_namelookup}s\nToplam Yanıt Süresi: %{time_total}s\n' \"https://${TARGET}:${PORT}\" || true
  "

echo "--------------------------------------------------------"
echo -e "${GREEN}Bağlantı testi tamamlandı.${NC}"

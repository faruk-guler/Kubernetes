#!/usr/bin/env bash
# ==============================================================================
# Script: capture_pod_packet_trace.sh
# Description: Çalışan bir Pod'un network namespace'ine Ephemeral Container
#              (nicolaka/netshoot) bağlayarak canlı tcpdump paket analizi yapar.
# Kullanımı: ./capture_pod_packet_trace.sh <pod-adi> [namespace] [port]
# ==============================================================================
set -euo pipefail

POD_NAME="${1:-}"
NAMESPACE="${2:-default}"
TARGET_PORT="${3:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$POD_NAME" ]; then
    echo -e "${BOLD}Kullanım:${NC} $0 <pod-adi> [namespace] [port]"
    echo "Örnek:    $0 payment-service-789f847 default 8080"
    exit 1
fi

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}      CANLI POD AĞ VE PAKET İZLEME (TCPDUMP / NETSHOOT)         ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "Hedef Pod: ${BOLD}${POD_NAME}${NC} (Namespace: ${BOLD}${NAMESPACE}${NC})"
[ -n "$TARGET_PORT" ] && echo -e "Filtrelenen Port: ${BOLD}${TARGET_PORT}${NC}"
echo ""

FILTER=""
if [ -n "$TARGET_PORT" ]; then
    FILTER="port ${TARGET_PORT}"
fi

echo -e "${GREEN}Ephemeral Debug konteyneri başlatılıyor ve tcpdump dinleniyor...${NC}"
echo -e "${YELLOW}(Durdurmak için Ctrl+C tuşlarına basabilirsiniz)${NC}"
echo "--------------------------------------------------------"

# kubectl debug ile pod'un network namespace'ine bağlan ve tcpdump çalıştır
kubectl debug -q -i -t "$POD_NAME" -n "$NAMESPACE" \
  --image=nicolaka/netshoot:latest \
  --profile=netadmin \
  -- sh -c "tcpdump -nn -v -i any ${FILTER} -c 50" || true

echo "--------------------------------------------------------"
echo -e "${GREEN}Paket yakalama oturumu sonlandırıldı.${NC}"

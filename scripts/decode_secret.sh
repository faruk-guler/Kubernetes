#!/usr/bin/env bash
# ==============================================================================
# Script: decode_secret.sh
# Description: Verilen bir Kubernetes Secret içindeki Base64 kodlanmış tüm verileri çözümler.
# Kullanımı: ./decode_secret.sh <secret-adi> [namespace] [key]
# ==============================================================================
set -euo pipefail

SECRET_NAME="${1:-}"
NAMESPACE="${2:-default}"
SPECIFIC_KEY="${3:-}"

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$SECRET_NAME" ]; then
    echo -e "${BOLD}Kullanım:${NC} $0 <secret-adi> [namespace] [belirli-key]"
    exit 1
fi

if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}[HATA] '$SECRET_NAME' isimli Secret '$NAMESPACE' namespace'inde bulunamadı.${NC}"
    exit 1
fi

echo -e "${BOLD}${BLUE}--- Secret Çözümleniyor: ${SECRET_NAME} (Namespace: ${NAMESPACE}) ---${NC}"

if [ -n "$SPECIFIC_KEY" ]; then
    echo -e "${BOLD}${SPECIFIC_KEY}:${NC}"
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.${SPECIFIC_KEY}}" | base64 -d
    echo ""
else
    kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o json | awk -F'"' '
      /": "/ {
        key=$2
        val=$4
        if (key != "apiVersion" && key != "kind" && key != "type") {
          cmd = "echo " val " | base64 -d 2>/dev/null"
          cmd | getline decoded
          close(cmd)
          printf "\033[1;32m%s:\033[0m %s\n", key, decoded
        }
      }
    '
fi

echo "--------------------------------------------------------"

#!/usr/bin/env bash
# ==============================================================================
# Script: audit_cert_expirations.sh
# Description: Kümedeki tüm TLS Secret'larını ve Kubeadm sertifikalarının kalan sürelerini denetler.
# Kullanımı: ./audit_cert_expirations.sh [gün_eşiği]
# ==============================================================================
set -euo pipefail

EXPIRY_THRESHOLD_DAYS="${1:-30}"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}       KUBERNETES TLS VE APISERVER SERTİFİKA DENETÇİSİ         ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Uyarı Eşiği: ${EXPIRY_THRESHOLD_DAYS} günden az kalanlar"
echo ""

# 1. Kubeadm Kontrolü (Master üzerindeyse)
if command -v kubeadm &> /dev/null && [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo -e "${BOLD}1. Kubeadm Control-Plane Sertifikaları:${NC}"
    kubeadm certs check-expiration || true
    echo ""
fi

# 2. Kümedeki TLS Secret'larının Taranması
echo -e "${BOLD}2. Ingress ve Uygulama TLS Secret'ları Taranıyor...${NC}"
TLS_SECRETS=$(kubectl get secrets --all-namespaces --field-selector type=kubernetes.io/tls -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' || true)

if [ -z "$TLS_SECRETS" ]; then
    echo -e "   ${GREEN}✔ Kümede 'kubernetes.io/tls' tipinde hiçbir Secret bulunamadı.${NC}"
else
    NOW_EPOCH=$(date +%s)
    EXPIRY_SECONDS=$((EXPIRY_THRESHOLD_DAYS * 86400))

    while IFS= read -r line; do
        NS=$(echo "$line" | awk '{print $1}')
        SEC=$(echo "$line" | awk '{print $2}')

        CERT_DATA=$(kubectl get secret "$SEC" -n "$NS" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || true)
        if [ -n "$CERT_DATA" ]; then
            EXPIRY_DATE=$(echo "$CERT_DATA" | base64 -d 2>/dev/null | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2 || true)
            if [ -n "$EXPIRY_DATE" ]; then
                CERT_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null || true)
                if [ -n "$CERT_EPOCH" ]; then
                    DIFF_SECONDS=$((CERT_EPOCH - NOW_EPOCH))
                    DAYS_LEFT=$((DIFF_SECONDS / 86400))

                    if [ "$DAYS_LEFT" -lt 0 ]; then
                        echo -e "   ${RED}✖ [SÜRESİ DOLMUŞ] [$NS] $SEC -> $DAYS_LEFT gün önce doldu!${NC}"
                    elif [ "$DAYS_LEFT" -le "$EXPIRY_THRESHOLD_DAYS" ]; then
                        echo -e "   ${YELLOW}⚠ [YAKLAŞIYOR]   [$NS] $SEC -> Kalan Gün: $DAYS_LEFT (${EXPIRY_DATE})${NC}"
                    else
                        echo -e "   ${GREEN}✔ [GEÇERLİ]      [$NS] $SEC -> Kalan Gün: $DAYS_LEFT${NC}"
                    fi
                fi
            fi
        fi
    done <<< "$TLS_SECRETS"
fi

echo ""
echo -e "${BOLD}Sertifika Denetimi Tamamlandı.${NC}"

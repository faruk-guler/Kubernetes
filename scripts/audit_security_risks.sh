#!/usr/bin/env bash
# ==============================================================================
# Script: audit_security_risks.sh
# Description: Kümedeki güvenlik açıklarını (root, privileged, host access) denetler.
# Kullanımı: ./audit_security_risks.sh [namespace]
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

NAMESPACE="${1:---all-namespaces}"
NS_FLAG=""
if [ "$NAMESPACE" != "--all-namespaces" ]; then
    NS_FLAG="-n $NAMESPACE"
fi

echo -e "${BOLD}================================================================${NC}"
echo -e "${BOLD}         KUBERNETES GÜVENLİK VE SERTLEŞTİRME DENETÇİSİ         ${NC}"
echo -e "${BOLD}================================================================${NC}"
echo -e "Kapsam: ${NAMESPACE}"
echo ""

# 1. Privileged Konteyner Taraması
echo -e "${BOLD}1. Privileged: true Yetkisiyle Çalışan Konteynerler:${NC}"
PRIV_PODS=$(kubectl get pods $NS_FLAG -o jsonpath='{range .items[*]}{range .spec.containers[?(@.securityContext.privileged==true)]}{$.metadata.namespace}{"\t"}{$.metadata.name}{"\t"}{.name}{"\n"}{end}{end}' || true)

if [ -z "$PRIV_PODS" ]; then
    echo -e "   ${GREEN}✔ 'privileged: true' konteyner bulunamadı.${NC}"
else
    echo -e "   ${RED}✖ KRİTİK GÜVENLİK RİSKİ! Root seviyesinde tam donanım erişimli podlar:${NC}"
    echo "$PRIV_PODS" | awk '{print "     - [" $1 "] Pod: " $2 " (Konteyner: " $3 ")"}'
fi
echo ""

# 2. Host İzolasyonu Delen Podlar (hostPID, hostNetwork)
echo -e "${BOLD}2. Host İzolasyonunu Delen Podlar (hostPID / hostNetwork):${NC}"
HOST_PODS=$(kubectl get pods $NS_FLAG -o jsonpath='{range .items[?(@.spec.hostPID==true)]}{.metadata.namespace}{"\t"}{.metadata.name}{" (hostPID)\n"}{end}{range .items[?(@.spec.hostNetwork==true)]}{.metadata.namespace}{"\t"}{.metadata.name}{" (hostNetwork)\n"}{end}' | grep -v 'kube-system' || true)

if [ -z "$HOST_PODS" ]; then
    echo -e "   ${GREEN}✔ Kullanıcı namespace'lerinde host izolasyonu delen pod yok.${NC}"
else
    echo -e "   ${YELLOW}⚠ Uyarı: Host PID veya Network kullanan uygulama podları:${NC}"
    echo "$HOST_PODS" | awk '{print "     - [" $1 "] " $2 " " $3}'
fi
echo ""

# 3. Kaynak Limiti (Limits) Olmayan Konteynerler
echo -e "${BOLD}3. CPU / RAM Limitleri Belirlenmemiş Konteynerler:${NC}"
NO_LIMITS=$(kubectl get pods $NS_FLAG -o jsonpath='{range .items[*]}{range .spec.containers[?(!@.resources.limits)]}{$.metadata.namespace}{"\t"}{$.metadata.name}{"\t"}{.name}{"\n"}{end}{end}' | grep -v 'kube-system' || true)

if [ -z "$NO_LIMITS" ]; then
    echo -e "   ${GREEN}✔ Tüm konteynerlerde kaynak limitleri tanımlı.${NC}"
else
    LIMIT_COUNT=$(echo "$NO_LIMITS" | wc -l | tr -d ' ')
    echo -e "   ${YELLOW}⚠ Uyarı: Toplam ${LIMIT_COUNT} konteynerde LimitRange/limits bulunmuyor (OOM ve Noisy Neighbor riski).${NC}"
fi
echo ""

echo -e "${BOLD}Denetim Tamamlandı.${NC}"

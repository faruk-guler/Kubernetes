#!/usr/bin/env bash
# ==============================================================================
# Script: cluster_health_check.sh
# Description: Kapsamlı Kubernetes küme sağlık ve teşhis taraması yapar.
# Kullanımı: ./cluster_health_check.sh
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}          KUBERNETES KÜME GENEL SAĞLIK TARAMASI                ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo ""

# 1. Kubectl kontrolü
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[HATA] 'kubectl' komutu bulunamadı. Lütfen kubectl kurun.${NC}"
    exit 1
fi

# 2. Düğüm (Node) Durumları
echo -e "${BOLD}1. Düğüm (Node) Durumları Kontrol Ediliyor...${NC}"
NOT_READY_NODES=$(kubectl get nodes --no-headers | grep -v 'Ready' || true)

if [ -z "$NOT_READY_NODES" ]; then
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    echo -e "   ${GREEN}✔ Tüm düğümler SAĞLIKLI (${NODE_COUNT} Düğüm Ready durumda).${NC}"
else
    echo -e "   ${RED}✖ DİKKAT! Sağlıksız / NotReady Düğümler Tespit Edildi:${NC}"
    echo "$NOT_READY_NODES" | awk '{print "     - " $1 " Durum: " $2}'
fi

# Düğüm Kaynak Baskısı (Pressure) Kontrolleri
PRESSURES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[*]}{.type}:{.status}{" "}{end}{"\n"}{end}' | grep -E 'DiskPressure:True|MemoryPressure:True|PIDPressure:True' || true)
if [ -n "$PRESSURES" ]; then
    echo -e "   ${YELLOW}⚠ Uyarı: Aşağıdaki düğümlerde kaynak baskısı (Pressure) var:${NC}"
    echo "$PRESSURES" | awk '{print "     - " $0}'
else
    echo -e "   ${GREEN}✔ Düğümlerde Disk/Memory/PID baskısı bulunmuyor.${NC}"
fi
echo ""

# 3. Sorunlu Podların Taraması
echo -e "${BOLD}2. Sorunlu Podlar Taranıyor (CrashLoopBackOff, OOMKilled, Pending)...${NC}"
FAILED_PODS=$(kubectl get pods --all-namespaces --no-headers | grep -E 'CrashLoopBackOff|OOMKilled|Error|ImagePullBackOff|ErrImagePull|Pending|Terminating' || true)

if [ -z "$FAILED_PODS" ]; then
    echo -e "   ${GREEN}✔ Kümede hata veya bekleme durumunda olan hiçbir pod bulunamadı.${NC}"
else
    echo -e "   ${YELLOW}⚠ İnceleme Gerektiren Podlar:${NC}"
    echo "$FAILED_PODS" | awk '{printf "     - [%s] %-35s %s (Yeniden Başlatma: %s)\n", $1, $2, $4, $5}'
fi
echo ""

# 4. Control Plane Bileşenleri
echo -e "${BOLD}3. Temel Sistem Bileşenleri (kube-system) Kontrol Ediliyor...${NC}"
SYSTEM_ISSUES=$(kubectl get pods -n kube-system --no-headers | grep -v 'Running' | grep -v 'Completed' || true)

if [ -z "$SYSTEM_ISSUES" ]; then
    echo -e "   ${GREEN}✔ Kube-System çekirdek servisleri sorunsuz çalışıyor.${NC}"
else
    echo -e "   ${RED}✖ Kube-System altında sorunlu bileşenler var:${NC}"
    echo "$SYSTEM_ISSUES" | awk '{print "     - " $1 " (" $3 ")"}'
fi
echo ""

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${GREEN}Tarama Tamamlandı.${NC}"

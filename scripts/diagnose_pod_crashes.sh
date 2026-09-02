#!/usr/bin/env bash
# ==============================================================================
# Script: diagnose_pod_crashes.sh
# Description: CrashLoopBackOff veya OOMKilled olan podların çıkış kodunu (Exit Code),
#              önceki (previous) loglarını ve ilişkili K8s eventlerini anında döker.
# Kullanımı: ./diagnose_pod_crashes.sh [pod-adi] [namespace]
# ==============================================================================
set -euo pipefail

POD_NAME="${1:-}"
NAMESPACE="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}         POD ÇÖKME VE KÖK NEDEN TEŞHİS ARACI (ROOT-CAUSE)       ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"

# Eğer pod adı verilmediyse, kümedeki ilk çöken podu otomatik bul
if [ -z "$POD_NAME" ]; then
    echo -e "${YELLOW}Pod adı belirtilmedi. Kümedeki CrashLoop/OOMKilled podlar taranıyor...${NC}"
    CRASHING=$(kubectl get pods --all-namespaces --no-headers | grep -E 'CrashLoopBackOff|OOMKilled|Error' | head -n 1 || true)
    if [ -z "$CRASHING" ]; then
        echo -e "${GREEN}✔ Harika! Kümede şu anda çöken veya CrashLoop'ta olan pod bulunamadı.${NC}"
        echo -e "Belirli bir podu incelemek için: $0 <pod-adi> [namespace]"
        exit 0
    fi
    NAMESPACE=$(echo "$CRASHING" | awk '{print $1}')
    POD_NAME=$(echo "$CRASHING" | awk '{print $2}')
    echo -e "Otomatik seçilen sorunlu pod: [${BOLD}${NAMESPACE}${NC}] ${BOLD}${POD_NAME}${NC}"
fi

NAMESPACE="${NAMESPACE:-default}"
echo -e "Hedef Pod: ${BOLD}${POD_NAME}${NC} (Namespace: ${BOLD}${NAMESPACE}${NC})"
echo ""

# 1. Konteyner Durumu ve Çıkış Kodları
echo -e "${BOLD}1. Son Durum (Last State) ve Çıkış Kodu Analizi:${NC}"
LAST_STATE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\tExitCode:"}{.lastState.terminated.exitCode}{"\tReason:"}{.lastState.terminated.reason}{"\tMessage:"}{.lastState.terminated.message}{"\n"}{end}' 2>/dev/null || true)

if [ -n "$LAST_STATE" ]; then
    echo "$LAST_STATE" | while IFS=$'\t' read -r cname exitcode reason message; do
        echo -e "   Konteyner: ${BOLD}${cname}${NC}"
        echo -e "   - ${RED}${exitcode}${NC} (${reason})"
        if [ "$exitcode" == "ExitCode:137" ]; then
            echo -e "     ${YELLOW}👉 137 Kodu: Konteyner Linux OOMKiller (Out Of Memory) tarafından öldürülmüş veya SIGKILL (kill -9) almış! Kaynak limitlerini (limits.memory) artırın.${NC}"
        elif [ "$exitcode" == "ExitCode:1" ]; then
            echo -e "     ${YELLOW}👉 1 Kodu: Uygulama kodunda veya başlangıç betiğinde (Entrypoint) genel hata fırlatıldı.${NC}"
        elif [ "$exitcode" == "ExitCode:143" ]; then
            echo -e "     ${YELLOW}👉 143 Kodu: Konteyner SIGTERM ile düzgün kapatılmak istendi ama zaman aşımına uğradı.${NC}"
        fi
        [ -n "$message" ] && echo -e "   - Mesaj: $message"
    done
else
    echo -e "   ${YELLOW}Detaylı lastState bilgisi bulunamadı.${NC}"
fi
echo ""

# 2. Önceki Konteynerin Çökme Anındaki Logları
echo -e "${BOLD}2. Çökmeden Önceki Son Loglar (kubectl logs --previous):${NC}"
echo "--------------------------------------------------------"
kubectl logs "$POD_NAME" -n "$NAMESPACE" --previous --tail=25 2>/dev/null || kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=25 2>/dev/null || echo -e "${YELLOW}Log kaydı alınamadı.${NC}"
echo "--------------------------------------------------------"
echo ""

# 3. İlgili Kubernetes Olayları (Events)
echo -e "${BOLD}3. Pod ile İlgili Son Kubernetes Olayları (Events):${NC}"
kubectl get events -n "$NAMESPACE" --field-selector "involvedObject.name=${POD_NAME}" --sort-by='.lastTimestamp' | tail -n 8 || true
echo ""
echo -e "${GREEN}Teşhis tamamlandı.${NC}"

#!/usr/bin/env bash
# ==============================================================================
# Script: setup_local_lab.sh
# Description: K3d veya Kind kullanarak tek komutla 1 Control-Plane + 2 Worker
#              düğümlü yerel laboratuvar kümesini kurar veya temizler.
# Kullanımı: ./setup_local_lab.sh <create|destroy|status> [küme-adı]
# ==============================================================================
set -euo pipefail

ACTION="${1:-create}"
CLUSTER_NAME="${2:-k8s-local-lab}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Motor Tespiti (k3d veya kind)
ENGINE=""
if command -v k3d &> /dev/null; then
    ENGINE="k3d"
elif command -v kind &> /dev/null; then
    ENGINE="kind"
else
    echo -e "${RED}[HATA] Sisteminizde 'k3d' veya 'kind' bulunamadı.${NC}"
    echo "Lütfen birini kurun:"
    echo "  - k3d : https://k3d.io"
    echo "  - kind: https://kind.sigs.k8s.io"
    exit 1
fi

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}    YEREL KUBERNETES TEST LABORATUVARI (${ENGINE^^})             ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "İşlem: ${BOLD}${ACTION}${NC} | Küme: ${BOLD}${CLUSTER_NAME}${NC} | Motor: ${BOLD}${ENGINE}${NC}"
echo ""

case "$ACTION" in
    create)
        echo -e "${BOLD}1. Laboratuvar Kümesi Oluşturuluyor (1 Server + 2 Worker)...${NC}"
        if [ "$ENGINE" == "k3d" ]; then
            # k3d ile küme oluştur
            k3d cluster create "$CLUSTER_NAME" \
                --servers 1 \
                --agents 2 \
                --port "80:80@loadbalancer" \
                --port "443:443@loadbalancer" \
                --k3s-arg "--disable=traefik@server:0"
        else
            # kind ile küme oluştur (multi-node config)
            cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF
        fi

        echo ""
        echo -e "${BOLD}2. Düğümlerin Hazır Olması Bekleniyor...${NC}"
        kubectl wait --for=condition=Ready nodes --all --timeout=120s
        echo ""
        echo -e "${GREEN}✔ Laboratuvar kümeniz kullanıma hazır!${NC}"
        kubectl get nodes -o wide
        ;;

    destroy)
        echo -e "${YELLOW}Laboratuvar kümesi siliniyor: ${CLUSTER_NAME}...${NC}"
        if [ "$ENGINE" == "k3d" ]; then
            k3d cluster delete "$CLUSTER_NAME"
        else
            kind delete cluster --name "$CLUSTER_NAME"
        fi
        echo -e "${GREEN}✔ Küme ve ilişkili tüm kaynaklar temizlendi.${NC}"
        ;;

    status)
        echo -e "${BOLD}Mevcut Laboratuvar Durumu:${NC}"
        if [ "$ENGINE" == "k3d" ]; then
            k3d cluster list
        else
            kind get clusters
        fi
        echo ""
        echo -e "${BOLD}Kubectl Bağlantısı:${NC}"
        kubectl cluster-info 2>/dev/null || echo -e "${YELLOW}Aktif bağlantı yok.${NC}"
        ;;

    *)
        echo -e "${RED}[HATA] Geçersiz işlem: '$ACTION'. Geçerli seçenekler: create, destroy, status.${NC}"
        exit 1
        ;;
esac

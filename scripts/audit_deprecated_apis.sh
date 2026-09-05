#!/bin/bash
set -euo pipefail

# ==============================================================================
# SRE Script: audit_deprecated_apis.sh
# Açıklama: Kubernetes kümesi güncellenmeden önce (Örn: 1.28 -> 1.30) 
#           kaldırılan (deprecated/removed) API versiyonlarını tespit eder.
# Bağımlılıklar: pluto (veya kubent - ikisinden biri çalışır)
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Kubernetes Deprecated API Tarayıcısı ===${NC}"
echo "Küme API Server ile iletişim kuruluyor..."

# Pluto kurulum kontrolü
if ! command -v pluto &> /dev/null; then
    echo -e "${RED}[HATA] 'pluto' aracı bulunamadı.${NC}"
    echo "Kurulum (Linux): curl -s https://raw.githubusercontent.com/FairwindsOps/pluto/master/scripts/install.sh | bash"
    echo "Alternatif olarak 'kubent' (Kube No Trouble) kullanabilirsiniz."
    
    # Kubent alternatifi kontrolü
    if command -v kubent &> /dev/null; then
        echo -e "${GREEN}[BİLGİ] 'kubent' bulundu. Kubent ile tarama başlatılıyor...${NC}"
        kubent
        exit 0
    else
        exit 1
    fi
fi

# Pluto ile tarama
echo -e "${GREEN}[BİLGİ] Pluto aracı ile canlı küme taranıyor...${NC}"
echo "Bu işlem kümedeki tüm yapılandırmaları indireceği için birkaç saniye sürebilir."
echo "----------------------------------------------------------------------"

# 'helm' yüklü ise helm release'lerini de tara
if command -v helm &> /dev/null; then
    echo -e "${YELLOW}[BİLGİ] Helm release'leri taranıyor...${NC}"
    pluto detect-helm -owide || true
    echo "----------------------------------------------------------------------"
fi

echo -e "${YELLOW}[BİLGİ] Canlı kümedeki (In-Cluster) nesneler taranıyor...${NC}"
pluto detect-api-resources -owide || true

echo "----------------------------------------------------------------------"
echo -e "${GREEN}[TAMAMLANDI] Lütfen 'REMOVED' (Kaldırıldı) veya 'DEPRECATED' (Eskidi) yazan nesneleri küme güncellemesinden ÖNCE güncelleyin.${NC}"

#!/bin/bash
set -euo pipefail

# ==============================================================================
# SRE Script: backup_pvc_to_local.sh
# Açıklama: Canlı ortamda çalışan bir Pod'un bağlı olduğu kalıcı disk (PVC)
#           içeriğini, Pod üzerinde ek disk alanı kaplamadan, STDOUT akışı
#           üzerinden yerel bilgisayara anlık .tar.gz olarak yedekler.
# Kullanım: ./backup_pvc_to_local.sh <namespace> <pod_ismi> <mount_yolu> [cikti_klasoru]
# Örnek   : ./backup_pvc_to_local.sh production postgres-0 /var/lib/postgresql/data ./backups
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ "$#" -lt 3 ]; then
    echo -e "${RED}[HATA] Eksik parametre!${NC}"
    echo "Kullanım: $0 <namespace> <pod_ismi> <mount_yolu> [cikti_klasoru]"
    echo "Örnek   : $0 default redis-master-0 /data ./pvc_backups"
    exit 1
fi

NAMESPACE="$1"
POD_NAME="$2"
MOUNT_PATH="$3"
OUTPUT_DIR="${4:-.}"

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${OUTPUT_DIR}/${NAMESPACE}_${POD_NAME}_${TIMESTAMP}.tar.gz"

echo -e "${BLUE}=== Kubernetes Canlı PVC Yedekleme Aracı ===${NC}"
echo -e "Namespace   : ${YELLOW}${NAMESPACE}${NC}"
echo -e "Pod         : ${YELLOW}${POD_NAME}${NC}"
echo -e "Dizin Yolu  : ${YELLOW}${MOUNT_PATH}${NC}"
echo -e "Hedef Dosya : ${YELLOW}${BACKUP_FILE}${NC}"
echo "----------------------------------------------------------------------"

# 1. Pod durumunu doğrula
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}[HATA] '$POD_NAME' isimli pod '$NAMESPACE' isim alanında bulunamadı.${NC}"
    exit 1
fi

# 2. Pod içinde dizin var mı kontrol et
echo -e "${YELLOW}[1/3]${NC} Pod içerisindeki dizin doğrulanıyor..."
if ! kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -d "$MOUNT_PATH" &> /dev/null; then
    echo -e "${RED}[HATA] Pod içerisinde '$MOUNT_PATH' dizini mevcut değil.${NC}"
    exit 1
fi

# 3. Canlı tar akışı başlat (Pod diski dolmaz, ağ üzerinden doğrudan yerele yazar)
echo -e "${YELLOW}[2/3]${NC} Canlı veri akışı başlatılıyor (tar + gzip)... Lütfen bekleyin."
START_TIME=$(date +%s)

kubectl exec -n "$NAMESPACE" "$POD_NAME" -- tar czf - -C "$MOUNT_PATH" . > "$BACKUP_FILE"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 4. Dosya boyutu ve bütünlük kontrolü
if [ -s "$BACKUP_FILE" ]; then
    FILE_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    echo -e "${YELLOW}[3/3]${NC} Bütünlük kontrolü yapılıyor..."
    
    # SHA256 hesaplama
    if command -v sha256sum &> /dev/null; then
        CHECKSUM=$(sha256sum "$BACKUP_FILE" | awk '{print $1}')
    else
        CHECKSUM=$(shasum -a 256 "$BACKUP_FILE" | awk '{print $1}')
    fi
    
    echo "----------------------------------------------------------------------"
    echo -e "${GREEN}[BAŞARILI] PVC yedeği başarıyla yerel diske aktarıldı!${NC}"
    echo -e "Dosya Boyutu : ${GREEN}${FILE_SIZE}${NC}"
    echo -e "Geçen Süre   : ${GREEN}${DURATION} saniye${NC}"
    echo -e "SHA256 Özeti : ${YELLOW}${CHECKSUM}${NC}"
    echo -e "Dosya Konumu : ${GREEN}${BACKUP_FILE}${NC}"
else
    echo -e "${RED}[HATA] Yedekleme dosyası boş oluşturuldu. Bir hata meydana gelmiş olabilir.${NC}"
    rm -f "$BACKUP_FILE"
    exit 1
fi

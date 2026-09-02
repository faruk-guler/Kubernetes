#!/usr/bin/env bash
# ==============================================================================
# Script: backup_etcd_snapshot.sh
# Description: Güvenli ve doğrulamalı etcd snapshot yedeği alır.
# Kullanımı: sudo ./backup_etcd_snapshot.sh [hedef-dizin]
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[HATA] Bu betik etcd sertifikalarına erişim için root (sudo) yetkisi gerektirir.${NC}"
    exit 1
fi

BACKUP_DIR="${1:-/var/backups/etcd}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

mkdir -p "$BACKUP_DIR"

echo -e "${BOLD}1. etcd Snapshot Yedeği Alınıyor...${NC}"

ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save "$BACKUP_FILE"

echo -e "   ${GREEN}✔ Yedek kaydedildi: $BACKUP_FILE${NC}"
echo ""

echo -e "${BOLD}2. Snapshot Bütünlüğü Doğrulanıyor...${NC}"
ETCDCTL_API=3 etcdctl --write-out=table snapshot status "$BACKUP_FILE"
echo ""

echo -e "${BOLD}3. Eski Yedekler Temizleniyor (7 günden eskiler)...${NC}"
find "$BACKUP_DIR" -type f -name "etcd-snapshot-*.db" -mtime +7 -exec rm -f {} \; 2>/dev/null || true
echo -e "   ${GREEN}✔ Temizlik tamamlandı.${NC}"

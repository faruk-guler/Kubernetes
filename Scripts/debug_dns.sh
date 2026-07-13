#!/bin/bash
# Description: Kümedeki DNS çözümlemelerini test etmek için geçici bir pod (dnstools) oluşturur ve nslookup yapar.
# Kullanımı: ./debug_dns.sh [hedef-domain]

TARGET=${1:-kubernetes.default}

echo "Geçici DNS test pod'u başlatılıyor (infoblox/dnstools)..."
echo "Hedef çözümleniyor: $TARGET"
echo "--------------------------------------------------------"

# Geçici bir pod oluşturup hedef adresi nslookup ile çözer
kubectl run dnstools-debug --image=infoblox/dnstools:latest --restart=Never --rm -i --tty -- nslookup "$TARGET"

echo "--------------------------------------------------------"
echo "Test tamamlandı, geçici pod otomatik olarak silindi."

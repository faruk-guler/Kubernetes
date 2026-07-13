#!/bin/bash
# Description: Kubeadm ile kurulan master düğümündeki apiserver/etcd sertifikalarının bitiş sürelerini kontrol eder.
# Kullanımı: ./check_cert_expirations.sh (Sadece master node üzerinde sudo ile çalıştırılmalıdır)

if [ "$EUID" -ne 0 ]; then
  echo "Lütfen bu betiği root (sudo) yetkisiyle çalıştırın."
  exit 1
fi

if ! command -v kubeadm &> /dev/null; then
    echo "Hata: 'kubeadm' komutu bulunamadı. Bu betik sadece Master (Control Plane) düğümü üzerinde çalışır."
    exit 1
fi

echo "Sertifika Bitiş Süreleri Kontrol Ediliyor..."
echo "--------------------------------------------------------"
kubeadm certs check-expiration
echo "--------------------------------------------------------"
echo "Not: Süresi dolan sertifikaları yenilemek için 'kubeadm certs renew all' komutunu kullanabilirsiniz."

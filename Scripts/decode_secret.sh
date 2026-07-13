#!/bin/bash
# Description: Verilen bir Kubernetes Secret içindeki Base64 kodlanmış verileri çözümler.
# Kullanımı: ./decode_secret.sh <secret-adi> [namespace]

SECRET_NAME=$1
NAMESPACE=${2:-default}

if [ -z "$SECRET_NAME" ]; then
    echo "Kullanım: $0 <secret-adi> [namespace]"
    exit 1
fi

echo "--- $SECRET_NAME (Namespace: $NAMESPACE) İçeriği Çözümleniyor ---"

# go-template kullanarak tüm .data alanındaki key'leri alıp base64decode işlemi uygular
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'

echo "--------------------------------------------------------"

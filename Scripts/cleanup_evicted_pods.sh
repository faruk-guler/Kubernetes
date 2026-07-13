#!/bin/bash
# Description: Kümedeki tüm "Evicted" (Kovulmuş) durumundaki pod'ları temizler.
# Kullanımı: ./cleanup_evicted_pods.sh

echo "Evicted durumundaki pod'lar aranıyor..."

# Evicted olan podları listele
EVICTED_PODS=$(kubectl get pods --all-namespaces | grep Evicted)

if [ -z "$EVICTED_PODS" ]; then
    echo "Harika! Kümede Evicted durumunda hiçbir pod bulunmuyor."
else
    echo "Aşağıdaki Evicted podlar siliniyor:"
    # namespace ve pod adını alıp silme komutuna yönlendir
    kubectl get pods --all-namespaces | grep Evicted | awk '{print "-n", $1, $2}' | xargs -L 1 kubectl delete pod
    echo "Temizlik tamamlandı."
fi

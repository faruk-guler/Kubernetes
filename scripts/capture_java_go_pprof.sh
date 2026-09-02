#!/bin/bash
set -euo pipefail

# ==============================================================================
# SRE Script: capture_java_go_pprof.sh
# Açıklama: Canlı ortamda çalışan Java (jstack/jmap) veya Go (pprof) podlarından
#           bellek sızıntısı (memory leak) veya CPU kilitlenmelerini analiz etmek
#           için Thread Dump ve Heap Dump veya pprof profili alır.
# Kullanım: ./capture_java_go_pprof.sh <namespace> <pod_ismi> <dil: java|go> [port]
# ==============================================================================

if [ "$#" -lt 3 ]; then
    echo "Kullanım: $0 <namespace> <pod_ismi> <dil: java|go> [port]"
    echo "Örnek (Java): $0 production payment-service java"
    echo "Örnek (Go)  : $0 production user-service go 8080"
    exit 1
fi

NAMESPACE=$1
POD_NAME=$2
LANG=$(echo "$3" | tr '[:upper:]' '[:lower:]')
PORT=${4:-8080}

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DUMP_DIR="/tmp/k8s_dumps/${POD_NAME}_${TIMESTAMP}"
mkdir -p "$DUMP_DIR"

echo -e "\033[0;32m[BİLGİ] $POD_NAME pod'u için profil alınıyor ($LANG)...\033[0m"

if [ "$LANG" == "java" ]; then
    echo "1. Ephemeral Container (Hata Ayıklama) başlatılıyor..."
    # Eğer asıl imajda jcmd/jstack yoksa JDK içeren geçici bir konteyner takarız
    # Java PID genelde 1'dir.
    
    # Pratik yol: Doğrudan pod içindeki jcmd'yi denemek:
    echo "Pod içinde jcmd aranıyor..."
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- jcmd 1 Thread.print > "$DUMP_DIR/thread_dump.txt" 2>/dev/null; then
        echo "Thread dump (jcmd) başarıyla alındı: $DUMP_DIR/thread_dump.txt"
    elif kubectl exec -n "$NAMESPACE" "$POD_NAME" -- jstack 1 > "$DUMP_DIR/thread_dump.txt" 2>/dev/null; then
        echo "Thread dump (jstack) başarıyla alındı: $DUMP_DIR/thread_dump.txt"
    else
        echo -e "\033[0;31m[HATA] Pod içinde JDK araçları bulunamadı. Ephemeral debug kullanmalısınız.\033[0m"
    fi

elif [ "$LANG" == "go" ]; then
    echo "1. Go pprof endpointine erişim sağlanıyor (localhost:$PORT)..."
    
    # Geçici bir port-forward başlat
    kubectl port-forward -n "$NAMESPACE" "$POD_NAME" "$PORT:$PORT" > /dev/null 2>&1 &
    PF_PID=$!
    
    # Port yönlendirmenin başlaması için biraz bekle
    sleep 2
    
    echo "30 saniyelik CPU profili alınıyor (Lütfen bekleyin)..."
    curl -sK -v "http://localhost:$PORT/debug/pprof/profile?seconds=30" > "$DUMP_DIR/cpu_profile.pprof"
    
    echo "Heap (Bellek) profili alınıyor..."
    curl -sK -v "http://localhost:$PORT/debug/pprof/heap" > "$DUMP_DIR/heap_profile.pprof"
    
    echo "Goroutine (Thread) profili alınıyor..."
    curl -sK -v "http://localhost:$PORT/debug/pprof/goroutine?debug=2" > "$DUMP_DIR/goroutine_dump.txt"
    
    # Port-forward'ı kapat
    kill $PF_PID
    
    echo -e "\033[0;32m[TAMAMLANDI] Go pprof dosyaları klasöre kaydedildi: $DUMP_DIR\033[0m"
    echo "İncelemek için: go tool pprof $DUMP_DIR/cpu_profile.pprof"
else
    echo "Geçersiz dil. Lütfen 'java' veya 'go' kullanın."
    exit 1
fi

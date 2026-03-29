#!/bin/bash
# ==============================================================================
# idle-monitor.sh — Monitor de inactividad.
# Apaga el streaming si no hay espectadores conectados durante un tiempo.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG="IDLE-MONITOR"

source "$SCRIPT_DIR/../config/config.sh"
load_config

# ==============================================================================
# OVERRIDE DE PARÁMETROS POR LÍNEA DE COMANDOS
# ==============================================================================
while getopts "t:s:i:" opt; do
    case $opt in
        t) IDLE_TIME="$OPTARG" ;;
        s) MONITOR_SERVICE="$OPTARG" ;;
        i) IDLE_CHECK_INTERVAL="$OPTARG" ;;
        \?) log_error "Uso: $0 -t 300 -s streaming-tv.service -i 30"; exit 1 ;;
    esac
done

require_cmd ss || exit 1

COUNTER=0

log_info "Monitor de inactividad iniciado | Límite: ${IDLE_TIME}s | Intervalo: ${IDLE_CHECK_INTERVAL}s"

# ==============================================================================
# BUCLE DE MONITOREO
# ==============================================================================
while true; do
    # Verificar que MediaMTX está corriendo antes de chequear conexiones
    if ! sudo docker ps -q -f name=mediamtx -f status=running >/dev/null 2>&1; then
        COUNTER=0
        sleep "$IDLE_CHECK_INTERVAL"
        continue
    fi

    # Contar conexiones activas en los puertos de streaming desde config
    RTMP_CONN=$(ss -tn state established "( sport = :${RTMP_PORT} )" 2>/dev/null | tail -n +2 | wc -l)
    RTSP_CONN=$(ss -tn state established "( sport = :${RTSP_PORT} )" 2>/dev/null | tail -n +2 | wc -l)
    WEBRTC_CONN=$(ss -tn state established "( sport = :${WEBRTC_PORT} )" 2>/dev/null | tail -n +2 | wc -l)
    HLS_CONN=$(ss -tn state established "( sport = :${HLS_PORT} )" 2>/dev/null | tail -n +2 | wc -l)

    READERS=$((RTMP_CONN + RTSP_CONN + WEBRTC_CONN + HLS_CONN))

    if [ "$READERS" -eq 0 ]; then
        # Solo sumar si el servicio realmente está encendido
        if sudo systemctl is-active --quiet "$MONITOR_SERVICE"; then
            COUNTER=$((COUNTER + IDLE_CHECK_INTERVAL))
            log_info "Sin espectadores. Inactividad: ${COUNTER}/${IDLE_TIME}s"
        else
            COUNTER=0
        fi
    else
        if [ "$COUNTER" -gt 0 ]; then
            log_info "Espectador detectado ($READERS conexiones). Reseteando contador."
        fi
        COUNTER=0
    fi

    # Si se alcanza el límite de tiempo sin clientes, apagar el servicio
    if [ "$COUNTER" -ge "$IDLE_TIME" ]; then
        log_warn "Límite de inactividad alcanzado (${IDLE_TIME}s). Deteniendo $MONITOR_SERVICE..."
        sudo systemctl stop "$MONITOR_SERVICE"
        logger -t "$LOG_TAG" "Servicio $MONITOR_SERVICE detenido por inactividad prolongada."
        COUNTER=0
    fi

    sleep "$IDLE_CHECK_INTERVAL"
done

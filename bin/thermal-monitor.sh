#!/bin/bash
# ==============================================================================
# thermal-monitor.sh — Monitor centinela de temperatura CPU.
# Detiene el servicio de streaming si la temperatura supera el umbral.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG="THERMAL-MONITOR"

source "$SCRIPT_DIR/../config/config.sh"
load_config

# ==============================================================================
# OVERRIDE DE PARÁMETROS POR LÍNEA DE COMANDOS
# ==============================================================================
while getopts "t:s:i:c:" opt; do
    case $opt in
        t) TEMP_LIMIT="$OPTARG" ;;
        s) MONITOR_SERVICE="$OPTARG" ;;
        i) THERMAL_CHECK_INTERVAL="$OPTARG" ;;
        c) THERMAL_COOLDOWN="$OPTARG" ;;
        \?) log_error "Uso: $0 -t 75 -s streaming-tv.service -i 10 -c 60"; exit 1 ;;
    esac
done

THERMAL_SENSOR="/sys/class/thermal/thermal_zone0/temp"
HYSTERESIS=5

if [ ! -f "$THERMAL_SENSOR" ]; then
    log_error "Sensor de temperatura no encontrado: $THERMAL_SENSOR"
    exit 1
fi

log_info "Monitoreo térmico iniciado: Límite ${TEMP_LIMIT}°C | Histéresis ${HYSTERESIS}°C | Servicio: ${MONITOR_SERVICE}"

SERVICE_STOPPED_BY_US=false

# ==============================================================================
# BUCLE DE MONITOREO
# ==============================================================================
while true; do
    TEMP_RAW=$(cat "$THERMAL_SENSOR")
    TEMP=$((TEMP_RAW / 1000))

    if [ "$TEMP" -ge "$TEMP_LIMIT" ]; then
        if sudo systemctl is-active --quiet "$MONITOR_SERVICE"; then
            log_warn "ALERTA TÉRMICA: ${TEMP}°C >= ${TEMP_LIMIT}°C. Deteniendo ${MONITOR_SERVICE}..."
            sudo systemctl stop "$MONITOR_SERVICE"
            logger -t "$LOG_TAG" "Servicio $MONITOR_SERVICE detenido por temperatura crítica (${TEMP}°C)"
            SERVICE_STOPPED_BY_US=true

            # Periodo de enfriamiento
            sleep "$THERMAL_COOLDOWN"
            continue
        fi
    fi

    # Histéresis: reiniciar solo cuando baje suficiente por debajo del límite
    if [ "$SERVICE_STOPPED_BY_US" = true ]; then
        RESTART_THRESHOLD=$((TEMP_LIMIT - HYSTERESIS))
        if [ "$TEMP" -le "$RESTART_THRESHOLD" ]; then
            log_info "Temperatura normalizada: ${TEMP}°C <= ${RESTART_THRESHOLD}°C. Reiniciando ${MONITOR_SERVICE}..."
            sudo systemctl start "$MONITOR_SERVICE" || log_warn "No se pudo reiniciar $MONITOR_SERVICE"
            SERVICE_STOPPED_BY_US=false
        fi
    fi

    sleep "$THERMAL_CHECK_INTERVAL"
done

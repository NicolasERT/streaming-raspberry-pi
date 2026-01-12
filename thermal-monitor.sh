#!/bin/bash

# --- VALORES POR DEFECTO ---
TEMP_LIMIT=75
SERVICE_TO_STOP="streaming-tv.service"
CHECK_INTERVAL=10
# ---------------------------

# Procesar parámetros nombrados
while getopts "t:s:i:" opt; do
  case $opt in
    t) TEMP_LIMIT="$OPTARG" ;;       # -t Límite de temperatura
    s) SERVICE_TO_STOP="$OPTARG" ;;  # -s Servicio a detener
    i) CHECK_INTERVAL="$OPTARG" ;;   # -i Intervalo de chequeo
    \?) echo "Uso: $0 -t 75 -s streaming-tv.service -i 10"; exit 1 ;;
  esac
done

echo "🔥 Monitoreo térmico activo: Límite ${TEMP_LIMIT}°C | Servicio: ${SERVICE_TO_STOP}"

while true; do
    # Leer temperatura
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP=$((TEMP_RAW / 1000))

    if [ "$TEMP" -ge "$TEMP_LIMIT" ]; then
        echo "⚠️ TEMPERATURA CRÍTICA: ${TEMP}°C. Deteniendo ${SERVICE_TO_STOP}..."
        
        # Detener el servicio mediante systemctl
        sudo systemctl stop "$SERVICE_TO_STOP"
        
        # Notificación opcional al log del sistema
        logger "THERMAL_MONITOR: Detenido $SERVICE_TO_STOP por alcanzar ${TEMP}C"
        
        # Esperar a que se enfríe antes de volver a monitorear (evita bucles rápidos)
        sleep 60 
    fi
    
    sleep "$CHECK_INTERVAL"
done

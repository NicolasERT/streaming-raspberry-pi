#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO
# ==============================================================================
TEMP_LIMIT=75
SERVICE_TO_STOP="streaming-tv.service"
CHECK_INTERVAL=10

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS NOMBRADOS
# ==============================================================================
while getopts "t:s:i:" opt; do
  case $opt in
    t) TEMP_LIMIT="$OPTARG" ;;       # Límite de temperatura en Celsius
    s) SERVICE_TO_STOP="$OPTARG" ;;  # Nombre del servicio .service a detener
    i) CHECK_INTERVAL="$OPTARG" ;;   # Intervalo de chequeo en segundos
    \?) echo "Uso: $0 -t 75 -s streaming-tv.service -i 10"; exit 1 ;;
  esac
done

echo "🔥 Monitoreo térmico iniciado: Límite ${TEMP_LIMIT}°C | Servicio: ${SERVICE_TO_STOP}"

# ==============================================================================
# BUCLE DE MONITOREO CONSTANTE
# ==============================================================================
while true; do
    # Leer temperatura del sensor térmico de la CPU (mili-grados Celsius)
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP=$((TEMP_RAW / 1000))
    else
        echo "❌ Error: No se pudo leer el sensor de temperatura."
        exit 1
    fi

    # Verificar si se ha superado el umbral de seguridad
    if [ "$TEMP" -ge "$TEMP_LIMIT" ]; then
        # Solo intentar detener si el servicio está activo
        if sudo systemctl is-active --quiet "$SERVICE_TO_STOP"; then
            echo "⚠️ ALERTA TÉRMICA: ${TEMP}°C. Deteniendo ${SERVICE_TO_STOP} por seguridad..."
            
            # Detener el servicio de streaming
            sudo systemctl stop "$SERVICE_TO_STOP"
            
            # Registrar el evento en el log del sistema (journalctl)
            logger -t THERMAL_MONITOR "ALERTA: Servicio $SERVICE_TO_STOP detenido por temperatura crítica (${TEMP}C)"
            
            # Periodo de enfriamiento: esperar un tiempo largo antes de reanudar el monitoreo
            # Esto evita que el servicio se detenga repetidamente en ráfagas cortas
            sleep 60
        fi
    fi
    
    # Pausa entre mediciones para no saturar la CPU
    sleep "$CHECK_INTERVAL"
done

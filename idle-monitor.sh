#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO
# ==============================================================================
IDLE_LIMIT=300         # Tiempo en segundos (5 minutos)
STREAM_PATH="live/stream"
SERVICE_TO_STOP="streaming-tv.service"
CHECK_INTERVAL=30      # Consultar cada 30 segundos
API_URL="http://localhost:9997/v3/paths/list"

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS
# ==============================================================================
while getopts "t:p:s:i:" opt; do
  case $opt in
    t) IDLE_LIMIT="$OPTARG" ;;     # Límite de inactividad
    p) STREAM_PATH="$OPTARG" ;;    # Nombre del stream en MediaMTX
    s) SERVICE_TO_STOP="$OPTARG" ;; # Servicio a detener
    i) CHECK_INTERVAL="$OPTARG" ;; # Intervalo de chequeo
  esac
done

COUNTER=0
echo "💤 Monitor de inactividad iniciado: $STREAM_PATH | Límite: $IDLE_LIMIT seg"

# ==============================================================================
# BUCLE DE MONITOREO
# ==============================================================================
while true; do
    # Consultar API de MediaMTX para obtener el conteo de lectores (readers)
    # Requiere el paquete 'jq' instalado
    READERS=$(curl -s "$API_URL" | jq -r ".items[] | select(.name==\"$STREAM_PATH\") | .readerCount" 2>/dev/null)

    # Si el stream no existe o no tiene lectores, sumamos al contador
    if [[ -z "$READERS" || "$READERS" == "0" ]]; then
        # Solo sumar si el servicio realmente está encendido
        if sudo systemctl is-active --quiet "$SERVICE_TO_STOP"; then
            COUNTER=$((COUNTER + CHECK_INTERVAL))
            echo "⏳ Sin espectadores en $STREAM_PATH. Inactividad: $COUNTER/$IDLE_LIMIT seg"
        else
            COUNTER=0
        fi
    else
        # Si hay alguien conectado, reseteamos el contador
        if [ "$COUNTER" -gt 0 ]; then echo "👤 ¡Espectador detectado! Reseteando contador."; fi
        COUNTER=0
    fi

    # Si se alcanza el límite de tiempo sin clientes, apagar el servicio
    if [ "$COUNTER" -ge "$IDLE_LIMIT" ]; then
        echo "🛑 Límite de inactividad alcanzado. Deteniendo $SERVICE_TO_STOP..."
        sudo systemctl stop "$SERVICE_TO_STOP"
        logger -t IDLE_MONITOR "Servicio $SERVICE_TO_STOP detenido por inactividad prolongada."
        COUNTER=0
    fi

    sleep "$CHECK_INTERVAL"
done

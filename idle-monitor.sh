#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO
# ==============================================================================
IDLE_LIMIT=300         # Tiempo en segundos (5 minutos)
SERVICE_TO_STOP="streaming-tv.service"
CHECK_INTERVAL=30      # Consultar cada 30 segundos

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS
# ==============================================================================
while getopts "t:s:i:" opt; do
  case $opt in
    t) IDLE_LIMIT="$OPTARG" ;;     # Límite de inactividad
    s) SERVICE_TO_STOP="$OPTARG" ;; # Servicio a detener
    i) CHECK_INTERVAL="$OPTARG" ;; # Intervalo de chequeo
  esac
done

COUNTER=0
echo "💤 Monitor de inactividad iniciado | Límite: $IDLE_LIMIT seg"

# ==============================================================================
# BUCLE DE MONITOREO
# ==============================================================================
while true; do
    # Contar conexiones activas en los puertos de streaming
    # RTMP: 1935, RTSP: 8554, WebRTC: 8889, HLS: 8888
    # Se excluyen las conexiones LISTEN y TIME-WAIT
    RTMP_CONN=$(ss -tn state established "( sport = :1935 )" 2>/dev/null | grep -c ESTAB || echo 0)
    RTSP_CONN=$(ss -tn state established "( sport = :8554 )" 2>/dev/null | grep -c ESTAB || echo 0)
    WEBRTC_CONN=$(ss -tn state established "( sport = :8889 )" 2>/dev/null | grep -c ESTAB || echo 0)
    HLS_CONN=$(ss -tn state established "( sport = :8888 )" 2>/dev/null | grep -c ESTAB || echo 0)
    
    READERS=$((RTMP_CONN + RTSP_CONN + WEBRTC_CONN + HLS_CONN))

    # Si el stream no existe o no tiene lectores, sumamos al contador
    if [[ -z "$READERS" || "$READERS" == "0" ]]; then
        # Solo sumar si el servicio realmente está encendido
        if sudo systemctl is-active --quiet "$SERVICE_TO_STOP"; then
            COUNTER=$((COUNTER + CHECK_INTERVAL))
            echo "⏳ Sin espectadores. Inactividad: $COUNTER/$IDLE_LIMIT seg"
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

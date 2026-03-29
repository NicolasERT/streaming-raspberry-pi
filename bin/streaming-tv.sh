#!/bin/bash
# ==============================================================================
# streaming-tv.sh — Captura video/audio USB y transmite vía RTMP a MediaMTX.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG="STREAMING-TV"

# Cargar configuración centralizada
source "$SCRIPT_DIR/../config/config.sh"
load_config

# ==============================================================================
# OVERRIDE DE PARÁMETROS POR LÍNEA DE COMANDOS
# ==============================================================================
while getopts "n:r:v:b:s:f:B:V:A:" opt; do
    case $opt in
        n) DEV_NAME="$OPTARG" ;;
        r) RTMP_URL="$OPTARG" ;;
        v) V_DEV="$OPTARG" ;;
        b) U_BUS="$OPTARG" ;;
        s) SIZE="$OPTARG" ;;
        f) FPS="$OPTARG" ;;
        B) VIDEO_BITRATE="$OPTARG" ;;
        V) AUDIO_VOLUME="$OPTARG" ;;
        A) AUDIO_SAMPLE_RATE="$OPTARG" ;;
        \?) log_error "Parámetro inválido"; exit 1 ;;
    esac
done

# Gestión de salida limpia: asegura liberar la cámara al detener el script
cleanup() {
    log_info "Deteniendo streaming, liberando $V_DEV..."
    sudo fuser -k "$V_DEV" 2>/dev/null || true
}
trap cleanup SIGINT SIGTERM EXIT

# ==============================================================================
# 1. PREPARACIÓN DEL ENTORNO (DOCKER & HARDWARE)
# ==============================================================================

# Verificar que el dispositivo de video existe
if [ ! -e "$V_DEV" ]; then
    log_error "Dispositivo de video no encontrado: $V_DEV"
    exit 1
fi

# Iniciar MediaMTX si el contenedor está apagado
if [ ! "$(sudo docker ps -q -f name=mediamtx)" ]; then
    log_info "Servidor mediamtx no detectado. Iniciando contenedor..."
    sudo docker start mediamtx || {
        log_error "No se pudo iniciar el contenedor mediamtx"
        exit 1
    }
    wait_for_container mediamtx 30 || exit 1
fi

# Reset Eléctrico del Bus USB para evitar bloqueos del hardware
log_info "Reiniciando bus USB $U_BUS..."
echo "$U_BUS" | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null 2>&1 || true
sleep 2
echo "$U_BUS" | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null 2>&1 || true
sleep 2

# Limpieza de procesos externos: mata cualquier app que use la cámara, excepto este script
CURRENT_PID=$$
for pid in $(sudo fuser "$V_DEV" 2>/dev/null | xargs); do
    if [ "$pid" != "$CURRENT_PID" ]; then
        log_warn "Cerrando proceso externo $pid que bloqueaba la cámara..."
        sudo kill -9 "$pid" 2>/dev/null || true
    fi
done

# ==============================================================================
# 2. CONFIGURACIÓN DE AUDIO
# ==============================================================================

# Detectar el índice de la tarjeta de sonido por nombre (ALSA)
CARD_NUM=$(arecord -l | grep "$DEV_NAME" | awk '{print $2}' | tr -d ':' | head -n 1)

if [ -n "$CARD_NUM" ]; then
    log_info "Activando micrófono en tarjeta $CARD_NUM..."
    sudo amixer -c "$CARD_NUM" cset numid=2 on > /dev/null 2>&1 || true
else
    log_warn "No se encontró el dispositivo de audio '$DEV_NAME'"
fi

# ==============================================================================
# 3. LANZAMIENTO DEL STREAMING (FFMPEG)
# ==============================================================================

OUTPUT_ARGS="-c:a aac -b:a 128k -f flv $RTMP_URL"

log_info "Iniciando stream: $SIZE @ ${FPS} FPS (RTMP) | Bitrate: $VIDEO_BITRATE | Volumen: ${AUDIO_VOLUME}dB"

ffmpeg -f alsa -ac 1 -i "plughw:${CARD_NUM:-0},0" \
    -f v4l2 -input_format mjpeg -video_size "$SIZE" -framerate "$FPS" -i "$V_DEV" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -flags +global_header \
    -x264-params "keyint=$((FPS * 1)):min-keyint=$((FPS * 1)):scenecut=0" \
    -b:v "$VIDEO_BITRATE" \
    -ar "$AUDIO_SAMPLE_RATE" \
    -af "aresample=async=1,asetpts=N/SR/TB,volume=${AUDIO_VOLUME}dB" \
    $OUTPUT_ARGS \
    2>> /var/log/streaming-tv-ffmpeg.log

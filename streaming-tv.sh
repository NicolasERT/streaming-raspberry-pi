#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO
# ==============================================================================
MODO="RTMP"
DEV_NAME="USB3.0 Video"
IP_DESTINO="localhost"
RTMP_URL="rtmp://localhost:1935/live/stream"
VIDEO_DEV="/dev/video0"
USB_BUS="5-1"
SIZE="1920x1080"
FPS="60"

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS NOMBRADOS
# ==============================================================================
while getopts "m:n:i:r:v:b:s:f:" opt; do
  case $opt in
    m) MODO="$OPTARG" ;;          # Modo: RTMP o UDP
    n) DEV_NAME="$OPTARG" ;;      # Nombre del dispositivo de audio
    i) IP_DESTINO="$OPTARG" ;;    # IP Destino para modo UDP
    r) RTMP_URL="$OPTARG" ;;      # URL del servidor RTMP
    v) VIDEO_DEV="$OPTARG" ;;     # Ruta del dispositivo de video
    b) USB_BUS="$OPTARG" ;;       # Bus USB para reset eléctrico (Bus-Puerto)
    s) SIZE="$OPTARG" ;;          # Resolución (ej. 1280x720)
    f) FPS="$OPTARG" ;;           # Cuadros por segundo (ej. 30)
    \?) echo "Uso inválido"; exit 1 ;;
  esac
done

# Gestión de salida limpia: asegura liberar la cámara al detener el script
trap "sudo fuser -k $VIDEO_DEV; exit" SIGINT SIGTERM

# ==============================================================================
# 1. PREPARACIÓN DEL ENTORNO (DOCKER & HARDWARE)
# ==============================================================================

# Iniciar MediaMTX si está en modo RTMP y el contenedor está apagado
if [ "$MODO" == "RTMP" ]; then
    if [ ! "$(sudo docker ps -q -f name=mediamtx)" ]; then
        echo "📦 Servidor mediamtx no detectado. Iniciando contenedor..."
        sudo docker start mediamtx
        sleep 3
    fi
fi

# Reset Eléctrico del Bus USB para evitar bloqueos del hardware
echo "⚡ Reiniciando bus USB $USB_BUS..."
echo "$USB_BUS" | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null
sleep 2
echo "$USB_BUS" | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null
sleep 2

# Limpieza de procesos externos: mata cualquier app que use la cámara, excepto este script
CURRENT_PID=$$
for pid in $(sudo fuser "$VIDEO_DEV" 2>/dev/null | xargs); do
    if [ "$pid" != "$CURRENT_PID" ]; then
        echo "🛡️ Cerrando proceso externo $pid que bloqueaba la cámara..."
        sudo kill -9 "$pid"
    fi
done

# ==============================================================================
# 2. CONFIGURACIÓN DE AUDIO
# ==============================================================================

# Detectar el índice de la tarjeta de sonido por nombre (ALSA)
CARD_NUM=$(arecord -l | grep "$DEV_NAME" | awk '{print $2}' | tr -d ':')

# Activar el interruptor de captura digital del micrófono
if [ ! -z "$CARD_NUM" ]; then
    echo "🎤 Activando micrófono en tarjeta $CARD_NUM..."
    sudo amixer -c "$CARD_NUM" cset numid=2 on > /dev/null
else
    echo "⚠️ Advertencia: No se encontró el dispositivo de audio '$DEV_NAME'"
fi

# ==============================================================================
# 3. LANZAMIENTO DEL STREAMING (FFMPEG)
# ==============================================================================

# Configurar argumentos de salida según el protocolo
if [ "$MODO" == "RTMP" ]; then
    # RTMP: Requiere AAC para audio y contenedor FLV
    OUTPUT_ARGS="-c:a aac -b:a 128k -f flv $RTMP_URL"
else
    # UDP: Uso de MP3 y contenedor MPEGTS para Windows/ffplay
    OUTPUT_ARGS="-c:a libmp3lame -b:a 96k -f mpegts udp://$IP_DESTINO:1234?pkt_size=1316"
fi

echo "🎥 Iniciando stream: $SIZE @ $FPS FPS ($MODO)..."

# Ejecución de FFmpeg con optimización de baja latencia
ffmpeg -f alsa -ac 1 -i "plughw:$CARD_NUM,0" \
    -f v4l2 -input_format mjpeg -video_size "$SIZE" -framerate "$FPS" -i "$VIDEO_DEV" \
    -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -flags +global_header \
    -x264-params "keyint=$((${FPS:-60} * 1)):min-keyint=$((${FPS:-60} * 1)):scenecut=0" -b:v 4000k \
    -ar 44100 -af "aresample=async=1,asetpts=N/SR/TB,volume=15dB" \
    $OUTPUT_ARGS

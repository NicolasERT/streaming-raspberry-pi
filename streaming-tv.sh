#!/bin/bash

# --- VALORES POR DEFECTO ---
MODO="RTMP"
DEV_NAME="USB3.0 Video"
IP_DESTINO="192.168.68.56"
RTMP_URL="rtmp://127.0.0.1:1935/live/stream"
VIDEO_DEV="/dev/video0"
USB_BUS="5-1"
SIZE="1920x1080"
FPS="60"
# ---------------------------

# Procesar parámetros nombrados
while getopts "m:n:i:r:v:b:s:f" opt; do
  case $opt in
    m) MODO="$OPTARG" ;;          # -m Modo (RTMP/UDP)
    n) DEV_NAME="$OPTARG" ;;      # -n Nombre del dispositivo
    i) IP_DESTINO="$OPTARG" ;;    # -i IP Destino (para UDP)
    r) RTMP_URL="$OPTARG" ;;      # -r URL de RTMP
    v) VIDEO_DEV="$OPTARG" ;;     # -v Dispositivo de video (/dev/videoX)
    b) USB_BUS="$OPTARG" ;;       # -b Bus USB (X-X)
    s) SIZE="$OPTARG" ;;          # -s Capturar Resolución
    f) FPS="$OPTARG" ;;           # -f Capturar FPS
    \?) echo "Uso inválido"; exit 1 ;;
  esac
done

# Al recibir orden de parada, mata el proceso de la cámara
trap "sudo fuser -k $VIDEO_DEV; exit" SIGINT SIGTERM

# 1. Verificar y levantar MediaMTX si es modo RTMP
if [ "$MODO" == "RTMP" ]; then
    if [ ! "$(sudo docker ps -q -f name=mediamtx)" ]; then
        echo "Servidor mediamtx detenido. Reiniciando..."
        sudo docker start mediamtx
        sleep 3
    fi
fi

# 2. Limpiar procesos y Reset Eléctrico USB
#sudo fuser -k $VIDEO_DEV 2>/dev/null
#echo "$USB_BUS" | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null
#sleep 2
#echo "$USB_BUS" | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null
#sleep 2

# Limpiar procesos de otros servicios, pero NO el nuestro
CURRENT_PID=$$
# Busca quién usa la cámara y mata solo si NO es nuestro PID actual
for pid in $(sudo fuser /dev/video0 2>/dev/null); do
    if [ "$pid" != "$CURRENT_PID" ]; then
        echo "Cerrando proceso externo $pid que bloqueaba la cámara..."
        sudo kill -9 "$pid"
    fi
done

# 3. Detectar Tarjeta de Sonido
CARD_NUM=$(arecord -l | grep "$DEV_NAME" | awk '{print $2}' | tr -d ':')

# 4. Activar Micrófono
if [ ! -z "$CARD_NUM" ]; then
    sudo amixer -c $CARD_NUM cset numid=2 on > /dev/null
fi

# 5. Definir parámetros de salida
if [ "$MODO" == "RTMP" ]; then
    OUTPUT_ARGS="-c:a aac -b:a 128k -f flv $RTMP_URL"
else
    OUTPUT_ARGS="-c:a libmp3lame -b:a 96k -f mpegts udp://$IP_DESTINO:1234?pkt_size=1316"
fi

# 6. Lanzamiento de FFmpeg
ffmpeg -f alsa -ac 1 -i plughw:$CARD_NUM,0 -f v4l2 -input_format mjpeg -video_size $SIZE -framerate $FPS -i $VIDEO_DEV \
-c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -flags +global_header \
-x264-params "keyint=$(($FPS * 1)):min-keyint=$(($FPS * 1)):scenecut=0" -b:v 4000k \
-ar 44100 -af "aresample=async=1,asetpts=N/SR/TB,volume=15dB" \
$OUTPUT_ARGS

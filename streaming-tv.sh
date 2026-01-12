#!/bin/bash

# Al recibir orden de parada, mata el proceso de la cámara y sale limpiamente
trap "sudo fuser -k /dev/video0; exit" SIGINT SIGTERM

# --- CONFIGURACIÓN ---
# Modos disponibles: "UDP" (a tu PC) o "RTMP" (al servidor local)
MODO="RTMP" 
IP_DESTINO="192.168.68.56"
RTMP_URL="rtmp://127.0.0.1:1935/live/stream"
# ---------------------

# 1. Verificar y levantar Docker si el modo es RTMP
if [ "$MODO" == "RTMP" ]; then
    if [ ! "$(sudo docker ps -q -f name=mediamtx)" ]; then
        echo "Servidor mediamtx detenido. Reiniciando..."
        sudo docker start mediamtx
        sleep 3
    fi
fi

# 2. Limpiar procesos y Reset Eléctrico USB (Bus 5, Puerto 1)
sudo fuser -k /dev/video0 2>/dev/null
echo '5-1' | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null
sleep 2
echo '5-1' | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null
sleep 2

# 3. Detectar Tarjeta de Sonido
CARD_NUM=$(arecord -l | grep "USB3.0 Video" | awk '{print $2}' | tr -d ':')

# 4. Activar Micrófono
if [ ! -z "$CARD_NUM" ]; then
    sudo amixer -c $CARD_NUM cset numid=2 on > /dev/null
fi

# 5. Definir parámetros de salida según el modo
if [ "$MODO" == "RTMP" ]; then
    # Configuración para RTMP (Usa AAC y contenedor FLV)
    OUTPUT_ARGS="-c:a aac -b:a 128k -f flv $RTMP_URL"
else
    # Configuración para UDP (Tu PC - Usa MP3 y contenedor MPEGTS)
    OUTPUT_ARGS="-c:a libmp3lame -b:a 96k -f mpegts udp://$IP_DESTINO:1234?pkt_size=1316"
fi

# 6. Lanzamiento de FFmpeg
ffmpeg -f alsa -ac 1 -i plughw:$CARD_NUM,0 -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 -i /dev/video0 \
-c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -flags +global_header \
-x264-params "keyint=30:min-keyint=30:scenecut=0" -b:v 1500k \
-ar 44100 -af "aresample=async=1,asetpts=N/SR/TB,volume=15dB" \
$OUTPUT_ARGS


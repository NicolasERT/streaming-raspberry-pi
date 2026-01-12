🛠️ MANUAL DE INSTALACIÓN: SISTEMA STREAMING-TV (NicolasRT)
Este documento detalla la configuración de la Raspberry Pi 5 para la captura y transmisión de audio/video profesional.
1. REQUISITOS PREVIOS
Instalar las herramientas de gestión de video, audio y el panel de control:
bash
sudo apt update
sudo apt install ffmpeg v4l-utils alsa-utils cockpit cockpit-pcp -y
Usa el código con precaución.

2. SERVIDOR DE MEDIOS (DOCKER)
Utilizamos MediaMTX para distribuir el video a la red y permitir visualización web.
Archivo: docker-compose.yml
yaml
services:
  mediamtx:
    image: bluenviron/mediamtx
    container_name: mediamtx
    restart: always
    ports:
      - "1935:1935" # RTMP Entrada
      - "8888:8888" # HLS Web
      - "8889:8889" # WebRTC Web (Baja latencia)
Usa el código con precaución.

Comando para iniciar: sudo docker compose up -d
3. EL SCRIPT DE CONTROL
Este archivo gestiona el hardware y la codificación del stream.
Archivo: /home/nicolasrt/streaming-tv.sh
bash
#!/bin/bash
# Limpiar procesos bloqueados
trap "sudo fuser -k /dev/video0; exit" SIGINT SIGTERM
sudo fuser -k /dev/video0 2>/dev/null

# Reset Eléctrico del Puerto USB 3.0 (Bus 5, Puerto 1)
echo '5-1' | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null
sleep 2
echo '5-1' | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null
sleep 2

# Detección automática de ID de Audio
CARD_NUM=$(arecord -l | grep "USB3.0 Video" | awk '{print $2}' | tr -d ':')

# Activar Micrófono
if [ ! -z "$CARD_NUM" ]; then
    amixer -c $CARD_NUM cset numid=2 on > /dev/null
fi

# Lanzar FFmpeg (Ajustado para Audio Mono y Estabilidad)
ffmpeg -f alsa -ac 1 -i plughw:$CARD_NUM,0 -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 -i /dev/video0 \
-c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -flags +global_header \
-x264-params "keyint=30:min-keyint=30:scenecut=0" -b:v 1500k \
-c:a aac -b:a 128k -ar 44100 -af "aresample=async=1,asetpts=N/SR/TB,volume=15dB" \
-f flv "rtmp://127.0.0.1:1935/live/stream"
Usa el código con precaución.

Permisos: chmod +x /home/nicolasrt/streaming-tv.sh
4. EL SERVICIO DE SISTEMA
Permite gestionar el stream desde Cockpit.
Archivo: /etc/systemd/system/streaming-tv.service
ini
[Unit]
Description=Servicio Streaming TV NicolasRT
After=network.target mediamtx.service

[Service]
ExecStart=/home/nicolasrt/streaming-tv.sh
Restart=always
RestartSec=5
User=nicolasrt

[Install]
WantedBy=multi-user.target
Usa el código con precaución.

Comandos de instalación:
bash
sudo systemctl daemon-reload
sudo systemctl enable streaming-tv.service
Usa el código con precaución.

5. RECEPTOR EN WINDOWS (.BAT)
Crea un archivo llamado Ver_Camara.bat en tu escritorio:
batch
@echo off
ffplay -i "rtmp://IP_DE_LA_PI:1935/live/stream" -fflags nobuffer -flags low_delay -probesize 1000000 -sync ext
Usa el código con precaución.

6. MANTENIMIENTO Y CONTROL
Acceso Web: https://IP_DE_LA_PI:9090 (Panel Cockpit para Start/Stop).
Ver Cámara en Navegador: http://IP_DE_LA_PI:8889/live/stream.
Ver logs de errores: journalctl -u streaming-tv.service -f.

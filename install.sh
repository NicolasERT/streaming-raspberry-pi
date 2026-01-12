#!/bin/bash

# --- CONFIGURACIÓN ---
USER_NAME="nicolasrt"
INSTALL_DIR="/home/$USER_NAME"
SERVICE_NAME="streaming-tv"

echo "🚀 Iniciando instalación del sistema Streaming-TV para $USER_NAME..."

# 1. Instalar dependencias del sistema
echo "📦 Instalando dependencias..."
sudo apt update && sudo apt install -y ffmpeg v4l-utils alsa-utils cockpit cockpit-pcp docker.io docker-compose

# 2. Asegurar permisos de Docker
sudo usermod -aG docker $USER_NAME

# 3. Crear el script de ejecución (streaming-tv.sh)
echo "📜 Creando script de ejecución..."
cat <<EOF > $INSTALL_DIR/$SERVICE_NAME.sh
#!/bin/bash
trap "sudo fuser -k /dev/video0; exit" SIGINT SIGTERM
sudo fuser -k /dev/video0 2>/dev/null
echo '5-1' | sudo tee /sys/bus/usb/drivers/usb/unbind > /dev/null
sleep 2
echo '5-1' | sudo tee /sys/bus/usb/drivers/usb/bind > /dev/null
sleep 2
CARD_NUM=\$(arecord -l | grep "USB3.0 Video" | awk '{print \$2}' | tr -d ':')
if [ ! -z "\$CARD_NUM" ]; then
    amixer -c \$CARD_NUM cset numid=2 on > /dev/null
fi
ffmpeg -f alsa -ac 1 -i plughw:\$CARD_NUM,0 -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 -i /dev/video0 \
-c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -flags +global_header \
-x264-params "keyint=30:min-keyint=30:scenecut=0" -b:v 1500k \
-c:a aac -b:a 128k -ar 44100 -af "aresample=async=1,asetpts=N/SR/TB,volume=15dB" \
-f flv "rtmp://127.0.0.1:1935/live/stream"
EOF

chmod +x $INSTALL_DIR/$SERVICE_NAME.sh
chown $USER_NAME:$USER_NAME $INSTALL_DIR/$SERVICE_NAME.sh

# 4. Crear el archivo Docker Compose para MediaMTX
echo "🐳 Configurando MediaMTX en Docker..."
cat <<EOF > $INSTALL_DIR/docker-compose.yml
services:
  mediamtx:
    image: bluenviron/mediamtx
    container_name: mediamtx
    restart: always
    ports:
      - "1935:1935"
      - "8888:8888"
      - "8889:8889"
EOF

# 5. Crear el servicio de Systemd
echo "⚙️ Configurando servicio de sistema..."
sudo cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Servicio Streaming TV NicolasRT
After=network.target

[Service]
ExecStart=$INSTALL_DIR/$SERVICE_NAME.sh
Restart=always
RestartSec=5
User=$USER_NAME

[Install]
WantedBy=multi-user.target
EOF

# 6. Activar servicios
echo "🔄 Recargando servicios..."
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME.service
cd $INSTALL_DIR && sudo docker-compose up -d

echo "✅ ¡Instalación completada!"
echo "Accede a Cockpit en: https://$(hostname -I | awk '{print $1}'):9090"

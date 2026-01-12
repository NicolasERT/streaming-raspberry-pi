#!/bash/bin
#!/bin/bash

# --- VALORES POR DEFECTO PARA LA INSTALACIÓN ---
USER_NAME="nicolasrt"
REPO_DIR=$(pwd)

# --- VALORES POR DEFECTO PARA EL STREAMING (Para inyectar en el servicio) ---
MODO="RTMP"
DEV_NAME="USB3.0 Video"
IP_DEST="192.168.68.56"
RTMP_URL="rtmp://127.0.0.1:1935/live/stream"
V_DEV="/dev/video0"
U_BUS="5-1"

# Procesar parámetros nombrados
while getopts "u:m:n:i:r:v:b:" opt; do
  case $opt in
    u) USER_NAME="$OPTARG" ;;     # Usuario
    m) MODO="$OPTARG" ;;          # Modo (RTMP/UDP)
    n) DEV_NAME="$OPTARG" ;;      # Nombre Dispositivo
    i) IP_DEST="$OPTARG" ;;       # IP Destino
    r) RTMP_URL="$OPTARG" ;;      # URL RTMP
    v) V_DEV="$OPTARG" ;;         # /dev/videoX
    b) U_BUS="$OPTARG" ;;         # Bus USB
    \?) echo "Uso: ./install.sh -u usuario -m MODO -n NAME ..."; exit 1 ;;
  esac
done

INSTALL_DIR="/home/$USER_NAME"

echo "🚀 Iniciando despliegue personalizado para $USER_NAME..."

# 1. Instalar dependencias
sudo apt update && sudo apt install -y ffmpeg v4l-utils alsa-utils cockpit docker.io docker-compose

# 2. Permisos Docker
sudo usermod -aG docker "$USER_NAME"

# 3. Copiar Script de Ejecución
if [ -f "$REPO_DIR/streaming-tv.sh" ]; then
    cp "$REPO_DIR/streaming-tv.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/streaming-tv.sh"
    chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/streaming-tv.sh"
fi

# 4. Configurar MediaMTX
if [ -f "$REPO_DIR/docker-compose.yml" ]; then
    cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/"
    chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/docker-compose.yml"
    cd "$INSTALL_DIR" && sudo docker-compose up -d
    cd "$REPO_DIR"
fi

# 5. Instalar y Personalizar Servicio de Systemd
if [ -f "$REPO_DIR/streaming-tv.service" ]; then
    sudo cp "$REPO_DIR/streaming-tv.service" /etc/systemd/system/
    
    # Inyectar parámetros en la línea ExecStart usando sed
    # Construimos la cadena de parámetros
    PARAMS="-m $MODO -n \"$DEV_NAME\" -i $IP_DEST -r $RTMP_URL -v $V_DEV -b $U_BUS"
    
    sudo sed -i "s/User=.*/User=$USER_NAME/" /etc/systemd/system/streaming-tv.service
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/streaming-tv.sh $PARAMS|" /etc/systemd/system/streaming-tv.service
    
    sudo systemctl daemon-reload
    sudo systemctl enable streaming-tv.service
    echo "✅ Servicio configurado con: $PARAMS"
fi

echo "---"
echo "✅ Instalación finalizada. Controla el servicio desde Cockpit."

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
SIZE="1920x1080"
FPS="60"

# Parámetros Monitor Térmico
TEMP_LIMIT="75"
MONITOR_SERVICE="streaming-tv.service"

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
    s) SIZE="$OPTARG" ;;          # Resolución (ej. 1920x1080)
    f) FPS="$OPTARG" ;;           # FPS (ej. 60)
    T) TEMP_LIMIT="$OPTARG" ;;     # Límite temperatura
    S) MONITOR_SERVICE="$OPTARG" ;; # Servicio a vigilar
    \?) echo "Uso: ./install.sh -u usuario -m MODO -n NAME ..."; exit 1 ;;
  esac
done

INSTALL_DIR="/home/$USER_NAME"

echo "🚀 Iniciando despliegue personalizado para $USER_NAME..."

# 1. Instalar dependencias
sudo apt update && sudo apt install -y ffmpeg v4l-utils alsa-utils cockpit docker.io docker-compose

# 2. Permisos Docker
sudo usermod -aG docker "$USER_NAME"

# 3. Configurar Scripts
for script in "streaming-tv.sh" "thermal-monitor.sh"; do
    if [ -f "$REPO_DIR/$script" ]; then
        cp "$REPO_DIR/$script" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/$script"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/$script"
    fi
done

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
    PARAMS="-m $MODO -n \"$DEV_NAME\" -i $IP_DEST -r $RTMP_URL -v $V_DEV -b $U_BUS -s $SIZE -f $FPS"
    
    sudo sed -i "s/User=.*/User=$USER_NAME/" /etc/systemd/system/streaming-tv.service
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/streaming-tv.sh $PARAMS|" /etc/systemd/system/streaming-tv.service
    
    sudo systemctl daemon-reload
    sudo systemctl enable streaming-tv.service
    echo "✅ Servicio configurado con: $PARAMS"
fi

# Configurar thermal-monitor.service
if [ -f "$REPO_DIR/thermal-monitor.service" ]; then
    sudo cp "$REPO_DIR/thermal-monitor.service" /etc/systemd/system/
    THERMAL_PARAMS="-t $TEMP_LIMIT -s $MONITOR_SERVICE"
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/thermal-monitor.sh $THERMAL_PARAMS|" /etc/systemd/system/thermal-monitor.service

    sudo systemctl daemon-reload
    sudo systemctl enable thermal-monitor.service
    echo "Monitor Térmico configurado a ${TEMP_LIMIT}C sobre el servicio ${MONITOR_SERVICE}."
fi

echo "---"
echo "✅ Instalación finalizada. Controla el servicio desde Cockpit."

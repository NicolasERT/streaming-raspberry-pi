#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO
# ==============================================================================
USER_NAME="nicolasrt"
REPO_DIR=$(pwd)

# Parámetros Streaming
MODO="RTMP"
DEV_NAME="USB3.0 Video"
IP_DEST="192.168.68.56"
RTMP_URL="rtmp://127.0.0.1:1935/live/stream"
V_DEV="/dev/video0"
U_BUS="5-1"
SIZE="1920x1080"
FPS="60"

# Parámetros Monitores (Térmico e Inactividad)
TEMP_LIMIT="75"
IDLE_TIME="300"
IDLE_CHECK_INTERVAL="30"
STREAM_PATH="live/stream"
MONITOR_SERVICE="streaming-tv.service"
API_USER="admin"
API_PASS="password"

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS NOMBRADOS
# ==============================================================================
while getopts "u:m:n:i:r:v:b:s:f:T:I:S:p:c:U:P:" opt; do
  case $opt in
    u) USER_NAME="$OPTARG" ;;
    m) MODO="$OPTARG" ;;
    n) DEV_NAME="$OPTARG" ;;
    i) IP_DEST="$OPTARG" ;;
    r) RTMP_URL="$OPTARG" ;;
    v) V_DEV="$OPTARG" ;;
    b) U_BUS="$OPTARG" ;;
    s) SIZE="$OPTARG" ;;
    f) FPS="$OPTARG" ;;
    T) TEMP_LIMIT="$OPTARG" ;;     # Límite Temperatura
    I) IDLE_TIME="$OPTARG" ;;      # Tiempo Inactividad (seg)
    S) MONITOR_SERVICE="$OPTARG" ;; # Servicio a vigilar
    p) STREAM_PATH="$OPTARG" ;;    # Path del stream para monitor de inactividad
    c) IDLE_CHECK_INTERVAL="$OPTARG" ;; # Intervalo chequeo de inactividad
    U) API_USER="$OPTARG" ;;       # Usuario API MediaMTX
    P) API_PASS="$OPTARG" ;;       # Contraseña API MediaMTX
    \?) echo "Uso: ./install.sh [opciones]"; exit 1 ;;
  esac
done

INSTALL_DIR="/home/$USER_NAME"

echo "🚀 Iniciando despliegue completo para $USER_NAME..."

# ==============================================================================
# 1. INSTALACIÓN DE DEPENDENCIAS
# ==============================================================================
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "📦 Instalando $1..."
        sudo apt update && sudo apt install -y "$2"
    else
        echo "✅ $1 ya está instalado."
    fi
}

install_if_missing "ffmpeg" "ffmpeg"
install_if_missing "v4l2-ctl" "v4l-utils"
install_if_missing "arecord" "alsa-utils"
install_if_missing "cockpit" "cockpit"
install_if_missing "docker" "docker.io"
install_if_missing "jq" "jq"

if ! docker compose version &> /dev/null; then
    echo "📦 Instalando Docker Compose Plugin..."
    sudo apt update && sudo apt install -y docker-compose-v2
fi

sudo usermod -aG docker "$USER_NAME"

# ==============================================================================
# 2. CONFIGURACIÓN DE SCRIPTS
# ==============================================================================
for script in "streaming-tv.sh" "thermal-monitor.sh" "idle-monitor.sh"; do
    if [ -f "$REPO_DIR/$script" ]; then
        echo "📜 Configurando $script..."
        cp "$REPO_DIR/$script" "$INSTALL_DIR/"
        sed -i 's/\r$//' "$INSTALL_DIR/$script"
        chmod +x "$INSTALL_DIR/$script"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/$script"
    fi
done

# ==============================================================================
# 3. CONFIGURACIÓN DE DOCKER (MediaMTX)
# ==============================================================================
if [ -f "$REPO_DIR/docker-compose.yml" ]; then
    cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/"
    chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/docker-compose.yml"
    
    if [ ! "$(sudo docker ps -a -q -f name=mediamtx)" ]; then
        cd "$INSTALL_DIR" && sudo docker compose up -d
        cd "$REPO_DIR"
    else
        sudo docker start mediamtx
    fi
fi

# ==============================================================================
# 4. PERSONALIZACIÓN DE SERVICIOS
# ==============================================================================

# streaming-tv.service
if [ -f "$REPO_DIR/streaming-tv.service" ]; then
    sudo cp "$REPO_DIR/streaming-tv.service" /etc/systemd/system/
    STREAM_PARAMS="-m $MODO -n \"$DEV_NAME\" -i $IP_DEST -r $RTMP_URL -v $V_DEV -b $U_BUS -s $SIZE -f $FPS"
    sudo sed -i "s/User=.*/User=$USER_NAME/" /etc/systemd/system/streaming-tv.service
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/streaming-tv.sh $STREAM_PARAMS|" /etc/systemd/system/streaming-tv.service
fi

# thermal-monitor.service
if [ -f "$REPO_DIR/thermal-monitor.service" ]; then
    sudo cp "$REPO_DIR/thermal-monitor.service" /etc/systemd/system/
    THERMAL_PARAMS="-t $TEMP_LIMIT -s $MONITOR_SERVICE"
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/thermal-monitor.sh $THERMAL_PARAMS|" /etc/systemd/system/thermal-monitor.service
    sudo systemctl enable thermal-monitor.service
fi

# idle-monitor.service
if [ -f "$REPO_DIR/idle-monitor.service" ]; then
    sudo cp "$REPO_DIR/idle-monitor.service" /etc/systemd/system/
    IDLE_PARAMS="-t $IDLE_TIME -s $MONITOR_SERVICE -p $STREAM_PATH -i $IDLE_CHECK_INTERVAL -U $API_USER -P $API_PASS"
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/idle-monitor.sh $IDLE_PARAMS|" /etc/systemd/system/idle-monitor.service
    sudo systemctl enable idle-monitor.service
fi

# ==============================================================================
# 5. APLICACIÓN DE CAMBIOS
# ==============================================================================
sudo systemctl daemon-reload

for SERVICE in "streaming-tv.service" "thermal-monitor.service" "idle-monitor.service"; do
    if sudo systemctl is-active --quiet "$SERVICE"; then
        sudo systemctl restart "$SERVICE"
    elif [[ "$SERVICE" != "streaming-tv.service" ]]; then
        sudo systemctl start "$SERVICE"
    fi
done

echo "✅ Instalación finalizada exitosamente."

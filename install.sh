#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO (INSTALACIÓN Y STREAMING)
# ==============================================================================
USER_NAME="nicolasrt"
REPO_DIR=$(pwd)

# Parámetros de Streaming
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

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS NOMBRADOS
# ==============================================================================
while getopts "u:m:n:i:r:v:b:s:f:T:S:" opt; do
  case $opt in
    u) USER_NAME="$OPTARG" ;;     # Usuario de Linux
    m) MODO="$OPTARG" ;;          # Modo: RTMP o UDP
    n) DEV_NAME="$OPTARG" ;;      # Nombre Dispositivo Audio
    i) IP_DEST="$OPTARG" ;;       # IP Destino (UDP)
    r) RTMP_URL="$OPTARG" ;;      # URL RTMP
    v) V_DEV="$OPTARG" ;;         # /dev/videoX
    b) U_BUS="$OPTARG" ;;         # Bus USB
    s) SIZE="$OPTARG" ;;          # Resolución
    f) FPS="$OPTARG" ;;           # FPS
    T) TEMP_LIMIT="$OPTARG" ;;    # Límite temperatura
    S) MONITOR_SERVICE="$OPTARG" ;; # Servicio a vigilar
    \?) echo "Uso: ./install.sh -u usuario -m MODO ..."; exit 1 ;;
  esac
done

INSTALL_DIR="/home/$USER_NAME"

# ==============================================================================
# FUNCIONES AUXILIARES
# ==============================================================================

# Instalación inteligente: evita reinstalar si el comando ya existe
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "📦 Instalando $1..."
        sudo apt update && sudo apt install -y "$2"
    else
        echo "✅ $1 ya está instalado."
    fi
}

echo "🚀 Iniciando despliegue personalizado para el usuario: $USER_NAME"

# ==============================================================================
# 1. INSTALACIÓN DE DEPENDENCIAS
# ==============================================================================
install_if_missing "ffmpeg" "ffmpeg"
install_if_missing "v4l2-ctl" "v4l-utils"
install_if_missing "arecord" "alsa-utils"
install_if_missing "cockpit" "cockpit"
install_if_missing "docker" "docker.io"

if ! docker compose version &> /dev/null; then
    echo "📦 Instalando Docker Compose Plugin..."
    sudo apt update && sudo apt install -y docker-compose-v2
else
    echo "✅ Docker Compose ya está listo."
fi

# Configurar permisos de grupo docker
sudo usermod -aG docker "$USER_NAME"

# ==============================================================================
# 2. DESPLIEGUE DE SCRIPTS Y DOCKER
# ==============================================================================

# Copiar y configurar scripts de control
for script in "streaming-tv.sh" "thermal-monitor.sh"; do
    if [ -f "$REPO_DIR/$script" ]; then
        echo "📜 Configurando $script..."
        cp "$REPO_DIR/$script" "$INSTALL_DIR/"
        sed -i 's/\r$//' "$INSTALL_DIR/$script" # Limpiar formato Windows (CRLF)
        chmod +x "$INSTALL_DIR/$script"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/$script"
    fi
done

# Configurar contenedor MediaMTX
if [ -f "$REPO_DIR/docker-compose.yml" ]; then
    echo "🐳 Verificando contenedor MediaMTX..."
    cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/"
    chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/docker-compose.yml"
    
    if [ ! "$(sudo docker ps -a -q -f name=mediamtx)" ]; then
        echo "📦 Desplegando nuevo contenedor MediaMTX..."
        cd "$INSTALL_DIR" && sudo docker compose up -d
        cd "$REPO_DIR"
    else
        echo "✅ El contenedor MediaMTX ya existe. Asegurando inicio..."
        sudo docker start mediamtx
    fi
fi

# ==============================================================================
# 3. INSTALACIÓN Y PERSONALIZACIÓN DE SERVICIOS
# ==============================================================================

# Configuración de streaming-tv.service
if [ -f "$REPO_DIR/streaming-tv.service" ]; then
    echo "⚙️ Personalizando servicio de streaming..."
    sudo cp "$REPO_DIR/streaming-tv.service" /etc/systemd/system/
    
    STREAM_PARAMS="-m $MODO -n \"$DEV_NAME\" -i $IP_DEST -r $RTMP_URL -v $V_DEV -b $U_BUS -s $SIZE -f $FPS"
    
    sudo sed -i "s/User=.*/User=$USER_NAME/" /etc/systemd/system/streaming-tv.service
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/streaming-tv.sh $STREAM_PARAMS|" /etc/systemd/system/streaming-tv.service
    
    sudo systemctl disable streaming-tv.service # Mantener manual por defecto
fi

# Configuración de thermal-monitor.service
if [ -f "$REPO_DIR/thermal-monitor.service" ]; then
    echo "⚙️ Personalizando monitor térmico..."
    sudo cp "$REPO_DIR/thermal-monitor.service" /etc/systemd/system/
    
    THERMAL_PARAMS="-t $TEMP_LIMIT -s $MONITOR_SERVICE"
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/thermal-monitor.sh $THERMAL_PARAMS|" /etc/systemd/system/thermal-monitor.service

    sudo systemctl enable thermal-monitor.service # Siempre activo
fi

# ==============================================================================
# 4. APLICACIÓN DE CAMBIOS Y REINICIO INTELIGENTE
# ==============================================================================
echo "🔄 Recargando demonios y verificando estados..."
sudo systemctl daemon-reload

for SERVICE in "streaming-tv.service" "thermal-monitor.service"; do
    if [ -f "/etc/systemd/system/$SERVICE" ]; then
        if sudo systemctl is-active --quiet "$SERVICE"; then
            echo "♻️ Reiniciando $SERVICE para aplicar cambios..."
            sudo systemctl restart "$SERVICE"
        else
            echo "✅ $SERVICE está listo (detenido)."
        fi
    fi
done

echo "-------------------------------------------------------"
echo "✅ INSTALACIÓN FINALIZADA CON ÉXITO"
echo "-------------------------------------------------------"
echo "Controla el sistema desde Cockpit o mediante systemctl."

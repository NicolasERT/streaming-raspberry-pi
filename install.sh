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
while getopts "u:m:n:i:r:v:b:s:f:T:S" opt; do
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

# --- FUNCIÓN DE INSTALACIÓN INTELIGENTE ---
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "📦 Instalando $1..."
        sudo apt update && sudo apt install -y "$2"
    else
        echo "✅ $1 ya está instalado."
    fi
}

# 1. Verificar dependencias una por una
# Formato: install_if_missing "comando" "paquete_apt"
install_if_missing "ffmpeg" "ffmpeg"
install_if_missing "v4l2-ctl" "v4l-utils"
install_if_missing "arecord" "alsa-utils"
install_if_missing "cockpit" "cockpit"
install_if_missing "docker" "docker.io"

# Docker Compose es un caso especial (plugin vs standalone)
if ! docker compose version &> /dev/null; then
    echo "📦 Instalando Docker Compose Plugin..."
    sudo apt update && sudo apt install -y docker-compose-v2
else
    echo "✅ Docker Compose ya está listo."
fi

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
    echo "🐳 Verificando contenedor MediaMTX..."
    cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/"
    chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/docker-compose.yml"
    
    # Comprobar si el contenedor ya existe (en cualquier estado: corriendo o detenido)
    if [ ! "$(sudo docker ps -a -q -f name=mediamtx)" ]; then
        echo "📦 Desplegando nuevo contenedor MediaMTX..."
        cd "$INSTALL_DIR" && sudo docker compose up -d
        cd "$REPO_DIR"
    else
        echo "✅ El contenedor MediaMTX ya existe. Asegurando que esté iniciado..."
        sudo docker start mediamtx
    fi
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
    sudo systemctl disable streaming-tv.service
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

# --- 5. REINICIO INTELIGENTE DE SERVICIOS ---
echo "🔄 Aplicando configuraciones y verificando estado..."

for SERVICE in "streaming-tv.service" "thermal-monitor.service"; do
    if [ -f "/etc/systemd/system/$SERVICE" ]; then
        # Recargar systemd para que reconozca los cambios en el archivo .service
        sudo systemctl daemon-reload
        
        # Verificar si el servicio ya estaba corriendo
        if sudo systemctl is-active --quiet "$SERVICE"; then
            echo "♻️ Reiniciando $SERVICE para aplicar nueva configuración..."
            sudo systemctl restart "$SERVICE"
        else
            echo "✅ $SERVICE actualizado (estaba detenido, se mantiene detenido)."
        fi
    fi
done

echo "---"
echo "✅ Instalación finalizada. Controla el servicio desde Cockpit."

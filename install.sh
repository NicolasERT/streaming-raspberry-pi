#!/bin/bash

# ==============================================================================
# CONFIGURACIÓN POR DEFECTO
# ==============================================================================
USER_NAME="nicolasrt"
REPO_DIR=$(pwd)
PLUGIN_SRC="$REPO_DIR/cockpit/pi-tv"
COCKPIT_DIR=""
HA_TOKEN=""
TUYA_ENTRY_ID="01KK2T254KGSTZP1RMJ76KY45J"
HA_BASE_URL="${HA_BASE_URL:-http://localhost:8123}"

# Parámetros Streaming
MODO="RTMP"
DEV_NAME="USB3.0 Video"
IP_DEST="localhost"
RTMP_URL="rtmp://localhost:1935/live/stream"
V_DEV="/dev/video0"
U_BUS="5-1"
SIZE="1920x1080"
FPS="60"

# Parámetros Monitores (Térmico e Inactividad)
TEMP_LIMIT="75"
IDLE_TIME="300"
IDLE_CHECK_INTERVAL="30"
MONITOR_SERVICE="streaming-tv.service"

# ==============================================================================
# PROCESAMIENTO DE PARÁMETROS NOMBRADOS
# ==============================================================================
while getopts "u:m:n:i:r:v:b:s:f:T:I:S:c:H:E:P:C:" opt; do
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
    c) IDLE_CHECK_INTERVAL="$OPTARG" ;; # Intervalo chequeo de inactividad
    H) HA_TOKEN="$OPTARG" ;;       # Token Home Assistant
    E) TUYA_ENTRY_ID="$OPTARG" ;;  # Config entry id de Tuya
    P) PLUGIN_SRC="$OPTARG" ;;     # Ruta fuente plugin Cockpit
    C) COCKPIT_DIR="$OPTARG" ;;    # Ruta destino plugin Cockpit
    \?) echo "Uso: ./install.sh [opciones]"; exit 1 ;;
  esac
done

INSTALL_DIR="/home/$USER_NAME"
if [ -z "$COCKPIT_DIR" ]; then
    COCKPIT_DIR="$INSTALL_DIR/.local/share/cockpit/pi-tv"
fi

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
install_if_missing "curl" "curl"

if ! docker compose version &> /dev/null; then
    echo "📦 Instalando Docker Compose Plugin..."
    sudo apt update && sudo apt install -y docker-compose-v2
fi

sudo usermod -aG docker "$USER_NAME"

# ==============================================================================
# 2. CONFIGURACIÓN DE SCRIPTS
# ==============================================================================
for script in "streaming-tv.sh" "thermal-monitor.sh" "idle-monitor.sh"; do
    if [ -f "$REPO_DIR/scripts/$script" ]; then
        echo "📜 Configurando $script..."
        cp "$REPO_DIR/scripts/$script" "$INSTALL_DIR/"
        sed -i 's/\r$//' "$INSTALL_DIR/$script"
        chmod +x "$INSTALL_DIR/$script"
        chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/$script"
    fi
done

if [ -f "$REPO_DIR/scripts/ha-script-run.sh" ]; then
    echo "📜 Instalando wrapper Home Assistant..."
    sudo cp "$REPO_DIR/scripts/ha-script-run.sh" /usr/local/bin/ha-script-run.sh
    sudo sed -i 's/\r$//' /usr/local/bin/ha-script-run.sh
    sudo chown root:root /usr/local/bin/ha-script-run.sh
    sudo chmod 750 /usr/local/bin/ha-script-run.sh
fi

if [ -d "$PLUGIN_SRC" ]; then
    echo "🧩 Instalando plugin Cockpit en $COCKPIT_DIR..."
    mkdir -p "$COCKPIT_DIR"
    cp "$PLUGIN_SRC/manifest.json" "$COCKPIT_DIR/manifest.json"
    cp "$PLUGIN_SRC/index.html" "$COCKPIT_DIR/index.html"
    cp "$PLUGIN_SRC/app.js" "$COCKPIT_DIR/app.js"
    cp "$PLUGIN_SRC/app.css" "$COCKPIT_DIR/app.css"
    chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR/.local"
else
    echo "⚠️ No existe la carpeta del plugin Cockpit: $PLUGIN_SRC"
fi

if [ -n "$HA_TOKEN" ]; then
    echo "🔐 Guardando token Home Assistant en /etc/ha-token..."
    printf '%s' "$HA_TOKEN" | sudo tee /etc/ha-token >/dev/null
    sudo chown root:root /etc/ha-token
    sudo chmod 600 /etc/ha-token
fi

# ==============================================================================
# 3. CONFIGURACIÓN DE DOCKER (MediaMTX)
# ==============================================================================
if [ -f "$REPO_DIR/docker/docker-compose.yml" ]; then
    cp "$REPO_DIR/docker/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
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
if [ -f "$REPO_DIR/services/streaming-tv.service" ]; then
    sudo cp "$REPO_DIR/services/streaming-tv.service" /etc/systemd/system/
    STREAM_PARAMS="-m $MODO -n \"$DEV_NAME\" -i $IP_DEST -r $RTMP_URL -v $V_DEV -b $U_BUS -s $SIZE -f $FPS"
    sudo sed -i "s/User=.*/User=$USER_NAME/" /etc/systemd/system/streaming-tv.service
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/streaming-tv.sh $STREAM_PARAMS|" /etc/systemd/system/streaming-tv.service
fi

# thermal-monitor.service
if [ -f "$REPO_DIR/services/thermal-monitor.service" ]; then
    sudo cp "$REPO_DIR/services/thermal-monitor.service" /etc/systemd/system/
    THERMAL_PARAMS="-t $TEMP_LIMIT -s $MONITOR_SERVICE"
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/thermal-monitor.sh $THERMAL_PARAMS|" /etc/systemd/system/thermal-monitor.service
    sudo systemctl enable thermal-monitor.service
fi

# idle-monitor.service
if [ -f "$REPO_DIR/services/idle-monitor.service" ]; then
    sudo cp "$REPO_DIR/services/idle-monitor.service" /etc/systemd/system/
    IDLE_PARAMS="-t $IDLE_TIME -s $MONITOR_SERVICE -i $IDLE_CHECK_INTERVAL"
    sudo sed -i "s|ExecStart=.*|ExecStart=$INSTALL_DIR/idle-monitor.sh $IDLE_PARAMS|" /etc/systemd/system/idle-monitor.service
    # Deshabilitado hasta que funcione correctamente
    sudo systemctl disable idle-monitor.service
    sudo systemctl stop idle-monitor.service
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

HA_TOKEN_EFFECTIVE=""
if [ -f /etc/ha-token ]; then
    HA_TOKEN_EFFECTIVE="$(tr -d '\r\n' < /etc/ha-token)"
fi

if [ -n "$HA_TOKEN_EFFECTIVE" ]; then
    echo "🔄 Recargando integración Tuya ($TUYA_ENTRY_ID)..."
    TUYA_PAYLOAD="{\"entry_id\":\"$TUYA_ENTRY_ID\"}"
    if curl -sS -f \
      -X POST \
      -H "Authorization: Bearer $HA_TOKEN_EFFECTIVE" \
      -H "Content-Type: application/json" \
      -d "$TUYA_PAYLOAD" \
      "$HA_BASE_URL/api/services/homeassistant/reload_config_entry" \
      >/dev/null; then
        echo "✅ Integración Tuya recargada"
    else
        echo "⚠️ No se pudo recargar Tuya en Home Assistant"
    fi
else
    echo "⚠️ No hay token HA en /etc/ha-token. Se omite recarga de Tuya"
fi

sudo systemctl restart cockpit || true

echo "✅ Instalación finalizada exitosamente."

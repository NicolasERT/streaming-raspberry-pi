#!/bin/bash
# ==============================================================================
# install.sh — Instalador interactivo para Streaming Raspberry Pi
#
# Interfaz TUI con whiptail para selección de componentes y configuración.
# Soporta modo no-interactivo con --non-interactive.
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/config/config.sh"
load_config

# ==============================================================================
# DETECCIÓN DE TUI
# ==============================================================================
INTERACTIVE=true
TUI_CMD=""

for arg in "$@"; do
    if [ "$arg" = "--non-interactive" ]; then
        INTERACTIVE=false
    fi
done

if [ "$INTERACTIVE" = true ]; then
    if command -v whiptail >/dev/null 2>&1; then
        TUI_CMD="whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        TUI_CMD="dialog"
    else
        echo "⚠️  No se encontró whiptail ni dialog. Ejecutando en modo no-interactivo."
        INTERACTIVE=false
    fi
fi

# Dimensiones de la terminal
TERM_LINES=$(tput lines 2>/dev/null || echo 24)
TERM_COLS=$(tput cols 2>/dev/null || echo 80)
DIALOG_H=$((TERM_LINES - 4))
DIALOG_W=$((TERM_COLS - 10))
[ "$DIALOG_H" -gt 30 ] && DIALOG_H=30
[ "$DIALOG_W" -gt 90 ] && DIALOG_W=90
[ "$DIALOG_H" -lt 20 ] && DIALOG_H=20
[ "$DIALOG_W" -lt 60 ] && DIALOG_W=60

# Componentes seleccionados (todos ON por defecto excepto idle y ha)
COMP_DEPS=ON
COMP_MEDIAMTX=ON
COMP_STREAMING=ON
COMP_THERMAL=ON
COMP_IDLE=OFF
COMP_COCKPIT=ON
COMP_HA=OFF

INSTALL_DIR="/home/$USER_NAME"
HA_TOKEN=""

# ==============================================================================
# FUNCIONES TUI
# ==============================================================================

tui_msgbox() {
    local title="$1" text="$2"
    $TUI_CMD --title "$title" --msgbox "$text" "$DIALOG_H" "$DIALOG_W"
}

tui_yesno() {
    local title="$1" text="$2"
    $TUI_CMD --title "$title" --yesno "$text" "$DIALOG_H" "$DIALOG_W"
}

tui_inputbox() {
    local title="$1" text="$2" default="$3"
    $TUI_CMD --title "$title" --inputbox "$text" 10 "$DIALOG_W" "$default" 3>&1 1>&2 2>&3
}

tui_radiolist() {
    local title="$1" text="$2"
    shift 2
    $TUI_CMD --title "$title" --radiolist "$text" "$DIALOG_H" "$DIALOG_W" 10 "$@" 3>&1 1>&2 2>&3
}

tui_gauge() {
    local text="$1" percent="$2"
    echo "$percent" | $TUI_CMD --title "Instalación" --gauge "$text" 8 "$DIALOG_W" 0
}

# ==============================================================================
# PANTALLAS DEL INSTALADOR
# ==============================================================================

show_welcome() {
    tui_msgbox "Streaming Raspberry Pi" \
"Bienvenido al instalador del sistema de streaming.

Este asistente le permitirá:
  • Seleccionar los componentes a instalar
  • Configurar los parámetros de cada componente
  • Revisar la configuración antes de aplicarla

Componentes disponibles:
  - Dependencias del sistema (ffmpeg, docker, etc.)
  - MediaMTX (servidor de medios)
  - Servicio de streaming (FFmpeg)
  - Monitor térmico
  - Monitor de inactividad
  - Plugin Cockpit (interfaz web)
  - Integración con Home Assistant

Pulse OK para continuar."
}

show_component_menu() {
    local result
    result=$($TUI_CMD --title "Selección de Componentes" \
        --checklist "Seleccione los componentes a instalar:" \
        "$DIALOG_H" "$DIALOG_W" 7 \
        "DEPS"      "Dependencias del sistema (ffmpeg, docker, etc.)" "$COMP_DEPS" \
        "MEDIAMTX"  "MediaMTX — Servidor de medios (Docker)"         "$COMP_MEDIAMTX" \
        "STREAMING" "Servicio de streaming FFmpeg"                     "$COMP_STREAMING" \
        "THERMAL"   "Monitor térmico de CPU"                           "$COMP_THERMAL" \
        "IDLE"      "Monitor de inactividad"                           "$COMP_IDLE" \
        "COCKPIT"   "Plugin Cockpit (interfaz web)"                    "$COMP_COCKPIT" \
        "HA"        "Integración Home Assistant"                       "$COMP_HA" \
        3>&1 1>&2 2>&3) || return 1

    COMP_DEPS=OFF; COMP_MEDIAMTX=OFF; COMP_STREAMING=OFF
    COMP_THERMAL=OFF; COMP_IDLE=OFF; COMP_COCKPIT=OFF; COMP_HA=OFF

    for item in $result; do
        item=$(echo "$item" | tr -d '"')
        case $item in
            DEPS)      COMP_DEPS=ON ;;
            MEDIAMTX)  COMP_MEDIAMTX=ON ;;
            STREAMING) COMP_STREAMING=ON ;;
            THERMAL)   COMP_THERMAL=ON ;;
            IDLE)      COMP_IDLE=ON ;;
            COCKPIT)   COMP_COCKPIT=ON ;;
            HA)        COMP_HA=ON ;;
        esac
    done
}

configure_general() {
    USER_NAME=$(tui_inputbox "Configuración General" "Usuario del sistema:" "$USER_NAME") || return 0
    INSTALL_DIR="/home/$USER_NAME"
}

configure_streaming() {
    local res_choice
    res_choice=$(tui_radiolist "Resolución" "Seleccione la resolución de video:" \
        "1920x1080" "Full HD (1080p)" "$([ "$SIZE" = "1920x1080" ] && echo ON || echo OFF)" \
        "1280x720"  "HD (720p)"       "$([ "$SIZE" = "1280x720" ] && echo ON || echo OFF)" \
        "854x480"   "SD (480p)"       "$([ "$SIZE" = "854x480" ] && echo ON || echo OFF)") || return 0
    SIZE="$res_choice"

    FPS=$(tui_inputbox "Video" "Fotogramas por segundo (FPS):" "$FPS") || return 0
    VIDEO_BITRATE=$(tui_inputbox "Video" "Bitrate de video (ej: 4000k):" "$VIDEO_BITRATE") || return 0
    V_DEV=$(tui_inputbox "Video" "Dispositivo de video:" "$V_DEV") || return 0
    U_BUS=$(tui_inputbox "Hardware" "Bus USB para reset eléctrico (Bus-Puerto):" "$U_BUS") || return 0
    RTMP_URL=$(tui_inputbox "Red" "URL del servidor RTMP:" "$RTMP_URL") || return 0

    DEV_NAME=$(tui_inputbox "Audio" "Nombre del dispositivo de audio (ALSA):" "$DEV_NAME") || return 0
    AUDIO_VOLUME=$(tui_inputbox "Audio" "Volumen de audio (dB, ej: 15):" "$AUDIO_VOLUME") || return 0
    AUDIO_SAMPLE_RATE=$(tui_inputbox "Audio" "Sample rate de audio (Hz):" "$AUDIO_SAMPLE_RATE") || return 0
}

configure_mediamtx() {
    RTMP_PORT=$(tui_inputbox "Puertos MediaMTX" "Puerto RTMP:" "$RTMP_PORT") || return 0
    HLS_PORT=$(tui_inputbox "Puertos MediaMTX" "Puerto HLS:" "$HLS_PORT") || return 0
    WEBRTC_PORT=$(tui_inputbox "Puertos MediaMTX" "Puerto WebRTC:" "$WEBRTC_PORT") || return 0
    RTSP_PORT=$(tui_inputbox "Puertos MediaMTX" "Puerto RTSP:" "$RTSP_PORT") || return 0
}

configure_thermal() {
    TEMP_LIMIT=$(tui_inputbox "Monitor Térmico" "Límite de temperatura CPU (°C):" "$TEMP_LIMIT") || return 0
    THERMAL_CHECK_INTERVAL=$(tui_inputbox "Monitor Térmico" "Intervalo de chequeo (segundos):" "$THERMAL_CHECK_INTERVAL") || return 0
    THERMAL_COOLDOWN=$(tui_inputbox "Monitor Térmico" "Periodo de enfriamiento (segundos):" "$THERMAL_COOLDOWN") || return 0
}

configure_idle() {
    IDLE_TIME=$(tui_inputbox "Monitor de Inactividad" "Tiempo sin espectadores para apagar (segundos):" "$IDLE_TIME") || return 0
    IDLE_CHECK_INTERVAL=$(tui_inputbox "Monitor de Inactividad" "Intervalo de chequeo (segundos):" "$IDLE_CHECK_INTERVAL") || return 0
}

configure_ha() {
    HA_BASE_URL=$(tui_inputbox "Home Assistant" "URL base de Home Assistant:" "$HA_BASE_URL") || return 0
    HA_TOKEN=$(tui_inputbox "Home Assistant" "Token de acceso de HA (dejar vacío para omitir):" "") || return 0
    HA_ENTITIES=$(tui_inputbox "Home Assistant" \
"Entidades HA (separadas por coma):
Ejemplo: scene.subir_canal_tv,scene.bajar_canal_tv" \
        "$HA_ENTITIES") || return 0
}

configure_cockpit() {
    COCKPIT_PLUGIN_DIR=$(tui_inputbox "Plugin Cockpit" \
        "Directorio de instalación del plugin:" \
        "${COCKPIT_PLUGIN_DIR:-/home/$USER_NAME/.local/share/cockpit/pi-tv}") || return 0
}

show_summary() {
    local summary=""
    summary+="CONFIGURACIÓN GENERAL\n"
    summary+="  Usuario: $USER_NAME\n"
    summary+="  Directorio: $INSTALL_DIR\n\n"

    summary+="COMPONENTES SELECCIONADOS\n"
    [ "$COMP_DEPS" = "ON" ]      && summary+="  ✔ Dependencias del sistema\n"
    [ "$COMP_MEDIAMTX" = "ON" ]  && summary+="  ✔ MediaMTX (puertos: $RTMP_PORT/$HLS_PORT/$WEBRTC_PORT/$RTSP_PORT)\n"
    [ "$COMP_STREAMING" = "ON" ] && summary+="  ✔ Streaming ($SIZE @ ${FPS}fps, bitrate: $VIDEO_BITRATE)\n"
    [ "$COMP_THERMAL" = "ON" ]   && summary+="  ✔ Monitor térmico (límite: ${TEMP_LIMIT}°C)\n"
    [ "$COMP_IDLE" = "ON" ]      && summary+="  ✔ Monitor inactividad (${IDLE_TIME}s)\n"
    [ "$COMP_COCKPIT" = "ON" ]   && summary+="  ✔ Plugin Cockpit\n"
    [ "$COMP_HA" = "ON" ]        && summary+="  ✔ Home Assistant ($HA_BASE_URL)\n"

    summary+="\n¿Desea proceder con la instalación?"

    tui_yesno "Resumen de Instalación" "$summary"
}

# ==============================================================================
# FUNCIONES DE INSTALACIÓN
# ==============================================================================

install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "📦 Instalando $1..."
        sudo apt-get update -qq && sudo apt-get install -y -qq "$2"
    else
        echo "✅ $1 ya está instalado."
    fi
}

do_install_dependencies() {
    echo "==> Instalando dependencias del sistema..."
    install_if_missing "ffmpeg" "ffmpeg"
    install_if_missing "v4l2-ctl" "v4l-utils"
    install_if_missing "arecord" "alsa-utils"
    install_if_missing "cockpit" "cockpit"
    install_if_missing "docker" "docker.io"
    install_if_missing "jq" "jq"

    if ! docker compose version &> /dev/null; then
        echo "📦 Instalando Docker Compose Plugin..."
        sudo apt-get update -qq && sudo apt-get install -y -qq docker-compose-v2
    fi

    sudo usermod -aG docker "$USER_NAME" 2>/dev/null || true
}

do_install_scripts() {
    echo "==> Instalando scripts en $INSTALL_DIR/bin/..."
    sudo mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/config"

    # Copiar scripts ejecutables
    for script in streaming-tv.sh thermal-monitor.sh idle-monitor.sh ha-script-run.sh; do
        if [ -f "$REPO_DIR/bin/$script" ]; then
            sudo cp "$REPO_DIR/bin/$script" "$INSTALL_DIR/bin/"
            sudo sed -i 's/\r$//' "$INSTALL_DIR/bin/$script"
            sudo chmod +x "$INSTALL_DIR/bin/$script"
            sudo chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/bin/$script"
        fi
    done

    # Copiar configuración
    if [ -f "$REPO_DIR/config/config.sh" ]; then
        sudo cp "$REPO_DIR/config/config.sh" "$INSTALL_DIR/config/"
        sudo cp "$REPO_DIR/config/default.env" "$INSTALL_DIR/config/"
        sudo sed -i 's/\r$//' "$INSTALL_DIR/config/config.sh"
        sudo sed -i 's/\r$//' "$INSTALL_DIR/config/default.env"
        sudo chmod +x "$INSTALL_DIR/config/config.sh"
        sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR/bin" "$INSTALL_DIR/config"
    fi

    # Instalar wrapper HA en ruta global
    if [ -f "$REPO_DIR/bin/ha-script-run.sh" ]; then
        sudo cp "$REPO_DIR/bin/ha-script-run.sh" /usr/local/bin/ha-script-run.sh
        sudo sed -i 's/\r$//' /usr/local/bin/ha-script-run.sh
        sudo chown root:root /usr/local/bin/ha-script-run.sh
        sudo chmod 750 /usr/local/bin/ha-script-run.sh
    fi
}

do_install_mediamtx() {
    echo "==> Configurando MediaMTX (Docker)..."

    sudo cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/"
    sudo chown "$USER_NAME:$USER_NAME" "$INSTALL_DIR/docker-compose.yml"

    # Copiar config para docker-compose env_file
    sudo mkdir -p "$INSTALL_DIR/config"
    sudo cp "$REPO_DIR/config/default.env" "$INSTALL_DIR/config/"

    if [ ! "$(sudo docker ps -a -q -f name=mediamtx)" ]; then
        cd "$INSTALL_DIR" && sudo docker compose up -d
        cd "$REPO_DIR"
    else
        sudo docker start mediamtx 2>/dev/null || true
    fi
}

do_install_service() {
    local service_name="$1"
    local template="$REPO_DIR/systemd/${service_name}"

    if [ ! -f "$template" ]; then
        echo "⚠️  Plantilla no encontrada: $template"
        return 1
    fi

    echo "==> Instalando servicio $service_name..."

    # Copiar y personalizar plantilla
    sudo cp "$template" /etc/systemd/system/
    sudo sed -i "s|__INSTALL_DIR__|$INSTALL_DIR|g" "/etc/systemd/system/$service_name"
    sudo sed -i "s|__USER_NAME__|$USER_NAME|g" "/etc/systemd/system/$service_name"
}

do_install_streaming() {
    do_install_service "streaming-tv.service"
    # No habilitar por defecto; se inicia manualmente desde Cockpit
}

do_install_thermal() {
    do_install_service "thermal-monitor.service"
    sudo systemctl enable thermal-monitor.service
}

do_install_idle() {
    do_install_service "idle-monitor.service"
    sudo systemctl enable idle-monitor.service
}

do_install_cockpit() {
    echo "==> Instalando plugin Cockpit en $COCKPIT_PLUGIN_DIR..."
    local plugin_src="$REPO_DIR/cockpit/pi-tv"

    if [ ! -d "$plugin_src" ]; then
        echo "⚠️  No se encontró el plugin en: $plugin_src"
        return 1
    fi

    mkdir -p "$COCKPIT_PLUGIN_DIR"
    cp "$plugin_src/manifest.json" "$COCKPIT_PLUGIN_DIR/"
    cp "$plugin_src/index.html" "$COCKPIT_PLUGIN_DIR/"
    cp "$plugin_src/app.js" "$COCKPIT_PLUGIN_DIR/"
    cp "$plugin_src/app.css" "$COCKPIT_PLUGIN_DIR/"

    echo "✅ Plugin Cockpit instalado."
}

do_install_ha() {
    echo "==> Configurando integración Home Assistant..."

    if [ -n "$HA_TOKEN" ]; then
        printf '%s' "$HA_TOKEN" | sudo tee "$HA_TOKEN_FILE" >/dev/null
        sudo chown root:root "$HA_TOKEN_FILE"
        sudo chmod 600 "$HA_TOKEN_FILE"
        echo "✅ Token HA guardado en $HA_TOKEN_FILE"
    else
        echo "⚠️  Token no proporcionado. Recuerda crear $HA_TOKEN_FILE manualmente."
    fi
}

do_save_config() {
    echo "==> Guardando configuración..."
    save_config

    # Generar config JSON para Cockpit
    local cockpit_config="/etc/streaming-pi/cockpit-config.json"
    local entities_json
    entities_json=$(echo "$HA_ENTITIES" | tr ',' '\n' | sed 's/^/"/;s/$/"/' | paste -sd',' | sed 's/^/[/;s/$/]/')

    sudo tee "$cockpit_config" > /dev/null <<EOF
{
  "hlsPort": $HLS_PORT,
  "webrtcPort": $WEBRTC_PORT,
  "rtmpPort": $RTMP_PORT,
  "rtspPort": $RTSP_PORT,
  "haEntities": $entities_json
}
EOF
    sudo chmod 644 "$cockpit_config"
    echo "✅ Configuración guardada."
}

do_apply_services() {
    echo "==> Aplicando cambios en servicios..."
    sudo systemctl daemon-reload

    for svc in streaming-tv.service thermal-monitor.service idle-monitor.service; do
        if sudo systemctl is-active --quiet "$svc"; then
            sudo systemctl restart "$svc"
        fi
    done

    # Reiniciar Cockpit si fue instalado
    if [ "$COMP_COCKPIT" = "ON" ]; then
        sudo systemctl restart cockpit 2>/dev/null || true
    fi
}

# ==============================================================================
# EJECUCIÓN CON BARRA DE PROGRESO
# ==============================================================================

run_installation() {
    local total=0 current=0

    [ "$COMP_DEPS" = "ON" ]      && total=$((total + 1))
    [ "$COMP_STREAMING" = "ON" ] && total=$((total + 1))  # scripts
    [ "$COMP_MEDIAMTX" = "ON" ]  && total=$((total + 1))
    [ "$COMP_STREAMING" = "ON" ] && total=$((total + 1))  # service
    [ "$COMP_THERMAL" = "ON" ]   && total=$((total + 1))
    [ "$COMP_IDLE" = "ON" ]      && total=$((total + 1))
    [ "$COMP_COCKPIT" = "ON" ]   && total=$((total + 1))
    [ "$COMP_HA" = "ON" ]        && total=$((total + 1))
    total=$((total + 2))  # save config + apply services

    progress() {
        current=$((current + 1))
        local pct=$((current * 100 / total))
        echo "$pct"
    }

    {
        if [ "$COMP_DEPS" = "ON" ]; then
            do_install_dependencies >&2
            progress
        fi

        # Scripts siempre se instalan si streaming o cualquier servicio está seleccionado
        if [ "$COMP_STREAMING" = "ON" ] || [ "$COMP_THERMAL" = "ON" ] || [ "$COMP_IDLE" = "ON" ]; then
            do_install_scripts >&2
            progress
        fi

        if [ "$COMP_MEDIAMTX" = "ON" ]; then
            do_install_mediamtx >&2
            progress
        fi

        if [ "$COMP_STREAMING" = "ON" ]; then
            do_install_streaming >&2
            progress
        fi

        if [ "$COMP_THERMAL" = "ON" ]; then
            do_install_thermal >&2
            progress
        fi

        if [ "$COMP_IDLE" = "ON" ]; then
            do_install_idle >&2
            progress
        fi

        if [ "$COMP_COCKPIT" = "ON" ]; then
            do_install_cockpit >&2
            progress
        fi

        if [ "$COMP_HA" = "ON" ]; then
            do_install_ha >&2
            progress
        fi

        do_save_config >&2
        progress

        do_apply_services >&2
        progress
    } | $TUI_CMD --title "Instalación" --gauge "Instalando componentes..." 8 "$DIALOG_W" 0
}

run_installation_non_interactive() {
    echo "🚀 Iniciando instalación no-interactiva para $USER_NAME..."

    [ "$COMP_DEPS" = "ON" ]      && do_install_dependencies

    if [ "$COMP_STREAMING" = "ON" ] || [ "$COMP_THERMAL" = "ON" ] || [ "$COMP_IDLE" = "ON" ]; then
        do_install_scripts
    fi

    [ "$COMP_MEDIAMTX" = "ON" ]  && do_install_mediamtx
    [ "$COMP_STREAMING" = "ON" ] && do_install_streaming
    [ "$COMP_THERMAL" = "ON" ]   && do_install_thermal
    [ "$COMP_IDLE" = "ON" ]      && do_install_idle
    [ "$COMP_COCKPIT" = "ON" ]   && do_install_cockpit
    [ "$COMP_HA" = "ON" ]        && do_install_ha

    do_save_config
    do_apply_services

    echo "✅ Instalación finalizada exitosamente."
}

show_result() {
    local status_text=""
    status_text+="Instalación completada.\n\n"

    for svc in streaming-tv.service thermal-monitor.service idle-monitor.service; do
        if systemctl list-unit-files "$svc" &>/dev/null; then
            local state
            state=$(systemctl is-active "$svc" 2>/dev/null || echo "no instalado")
            local enabled
            enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "—")
            status_text+="  $svc: $state ($enabled)\n"
        fi
    done

    status_text+="\nArchivos de configuración:\n"
    status_text+="  $CONFIG_SYSTEM_FILE\n"
    status_text+="  /etc/streaming-pi/cockpit-config.json\n"

    if [ -n "$HA_TOKEN" ]; then
        status_text+="\nToken HA: $HA_TOKEN_FILE\n"
    fi

    status_text+="\nAcceso:\n"
    status_text+="  Cockpit:  https://<IP>:9090\n"
    status_text+="  WebRTC:   http://<IP>:${WEBRTC_PORT}/live/stream\n"
    status_text+="  RTMP:     rtmp://<IP>:${RTMP_PORT}/live/stream\n"

    tui_msgbox "Resultado" "$status_text"
}

# ==============================================================================
# FLUJO PRINCIPAL
# ==============================================================================

if [ "$INTERACTIVE" = true ]; then
    show_welcome
    show_component_menu || { echo "Instalación cancelada."; exit 0; }
    configure_general

    [ "$COMP_STREAMING" = "ON" ] && configure_streaming
    [ "$COMP_MEDIAMTX" = "ON" ]  && configure_mediamtx
    [ "$COMP_THERMAL" = "ON" ]   && configure_thermal
    [ "$COMP_IDLE" = "ON" ]      && configure_idle
    [ "$COMP_HA" = "ON" ]        && configure_ha
    [ "$COMP_COCKPIT" = "ON" ]   && configure_cockpit

    show_summary || { echo "Instalación cancelada por el usuario."; exit 0; }

    run_installation
    show_result
else
    # Modo no-interactivo: procesar parámetros de CLI para override
    shift || true  # Quitar --non-interactive
    while getopts "u:s:f:r:v:b:T:H:n:" opt 2>/dev/null; do
        case $opt in
            u) USER_NAME="$OPTARG"; INSTALL_DIR="/home/$USER_NAME" ;;
            s) SIZE="$OPTARG" ;;
            f) FPS="$OPTARG" ;;
            r) RTMP_URL="$OPTARG" ;;
            v) V_DEV="$OPTARG" ;;
            b) U_BUS="$OPTARG" ;;
            T) TEMP_LIMIT="$OPTARG" ;;
            H) HA_TOKEN="$OPTARG"; COMP_HA=ON ;;
            n) DEV_NAME="$OPTARG" ;;
            *) ;;
        esac
    done

    run_installation_non_interactive
fi

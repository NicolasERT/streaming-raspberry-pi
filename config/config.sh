#!/usr/bin/env bash
# ==============================================================================
# config.sh — Librería helper compartida por todos los scripts del sistema.
#
# Uso: source este archivo al inicio de cada script.
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../config/config.sh"
# ==============================================================================

# Detectar directorio raíz del repositorio/instalación
if [ -z "${REPO_DIR:-}" ]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

CONFIG_SYSTEM_DIR="/etc/streaming-pi"
CONFIG_SYSTEM_FILE="$CONFIG_SYSTEM_DIR/config.env"
CONFIG_DEFAULT_FILE="$REPO_DIR/config/default.env"

# ==============================================================================
# load_config — Carga defaults y aplica overrides del sistema si existen.
# ==============================================================================
load_config() {
    if [ -f "$CONFIG_DEFAULT_FILE" ]; then
        set -a
        # shellcheck source=default.env
        . "$CONFIG_DEFAULT_FILE"
        set +a
    fi

    if [ -f "$CONFIG_SYSTEM_FILE" ]; then
        set -a
        # shellcheck source=/dev/null
        . "$CONFIG_SYSTEM_FILE"
        set +a
    fi
}

# ==============================================================================
# Logging — Funciones de log con tag consistente.
# Usa la variable LOG_TAG del script que llama, o "STREAMING-PI" por defecto.
# ==============================================================================
_log() {
    local level="$1"
    shift
    local tag="${LOG_TAG:-STREAMING-PI}"
    logger -t "$tag" -p "user.$level" "$*"
    echo "[$tag] $level: $*"
}

log_info()  { _log "info"    "$@"; }
log_warn()  { _log "warning" "$@"; }
log_error() { _log "err"     "$@"; }

# ==============================================================================
# require_cmd — Verifica que un comando existe en el PATH.
# Uso: require_cmd ffmpeg docker ss
# ==============================================================================
require_cmd() {
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Comando requerido no encontrado: $cmd"
            return 1
        fi
    done
}

# ==============================================================================
# validate_port — Valida que un valor sea un puerto válido (1-65535).
# ==============================================================================
validate_port() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        log_error "Puerto inválido para $name: $value (debe ser 1-65535)"
        return 1
    fi
}

# ==============================================================================
# validate_positive_int — Valida que un valor sea un entero positivo.
# ==============================================================================
validate_positive_int() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
        log_error "Valor inválido para $name: $value (debe ser entero positivo)"
        return 1
    fi
}

# ==============================================================================
# validate_config — Valida los parámetros cargados.
# ==============================================================================
validate_config() {
    local errors=0

    validate_positive_int "FPS" "${FPS:-0}"               || errors=$((errors + 1))
    validate_port "RTMP_PORT" "${RTMP_PORT:-0}"            || errors=$((errors + 1))
    validate_port "HLS_PORT" "${HLS_PORT:-0}"              || errors=$((errors + 1))
    validate_port "WEBRTC_PORT" "${WEBRTC_PORT:-0}"        || errors=$((errors + 1))
    validate_port "RTSP_PORT" "${RTSP_PORT:-0}"            || errors=$((errors + 1))
    validate_positive_int "TEMP_LIMIT" "${TEMP_LIMIT:-0}"  || errors=$((errors + 1))
    validate_positive_int "IDLE_TIME" "${IDLE_TIME:-0}"    || errors=$((errors + 1))

    if [ "$errors" -gt 0 ]; then
        log_error "Configuración inválida: $errors errores encontrados"
        return 1
    fi
}

# ==============================================================================
# wait_for_container — Espera a que un contenedor Docker esté corriendo.
# Uso: wait_for_container mediamtx 30
# ==============================================================================
wait_for_container() {
    local name="$1"
    local timeout="${2:-30}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        if [ "$(docker ps -q -f name="$name" -f status=running 2>/dev/null)" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    log_error "Timeout esperando contenedor $name (${timeout}s)"
    return 1
}

# ==============================================================================
# save_config — Guarda la configuración actual en el archivo del sistema.
# ==============================================================================
save_config() {
    sudo mkdir -p "$CONFIG_SYSTEM_DIR"
    {
        echo "# Generado por install.sh — $(date -Iseconds)"
        echo ""
        echo "# General"
        echo "USER_NAME=\"${USER_NAME}\""
        echo ""
        echo "# Video"
        echo "V_DEV=\"${V_DEV}\""
        echo "SIZE=\"${SIZE}\""
        echo "FPS=\"${FPS}\""
        echo "VIDEO_BITRATE=\"${VIDEO_BITRATE}\""
        echo ""
        echo "# Audio"
        echo "DEV_NAME=\"${DEV_NAME}\""
        echo "AUDIO_SAMPLE_RATE=\"${AUDIO_SAMPLE_RATE}\""
        echo "AUDIO_VOLUME=\"${AUDIO_VOLUME}\""
        echo ""
        echo "# USB"
        echo "U_BUS=\"${U_BUS}\""
        echo ""
        echo "# Red / RTMP"
        echo "RTMP_URL=\"${RTMP_URL}\""
        echo ""
        echo "# MediaMTX"
        echo "RTMP_PORT=\"${RTMP_PORT}\""
        echo "HLS_PORT=\"${HLS_PORT}\""
        echo "WEBRTC_PORT=\"${WEBRTC_PORT}\""
        echo "RTSP_PORT=\"${RTSP_PORT}\""
        echo ""
        echo "# Monitor térmico"
        echo "TEMP_LIMIT=\"${TEMP_LIMIT}\""
        echo "THERMAL_CHECK_INTERVAL=\"${THERMAL_CHECK_INTERVAL}\""
        echo "THERMAL_COOLDOWN=\"${THERMAL_COOLDOWN}\""
        echo ""
        echo "# Monitor de inactividad"
        echo "IDLE_TIME=\"${IDLE_TIME}\""
        echo "IDLE_CHECK_INTERVAL=\"${IDLE_CHECK_INTERVAL}\""
        echo ""
        echo "# Home Assistant"
        echo "HA_BASE_URL=\"${HA_BASE_URL}\""
        echo "HA_TOKEN_FILE=\"${HA_TOKEN_FILE}\""
        echo "HA_ENTITIES=\"${HA_ENTITIES}\""
        echo ""
        echo "# Cockpit"
        echo "COCKPIT_PLUGIN_DIR=\"${COCKPIT_PLUGIN_DIR}\""
        echo ""
        echo "# Servicio objetivo"
        echo "MONITOR_SERVICE=\"${MONITOR_SERVICE}\""
    } | sudo tee "$CONFIG_SYSTEM_FILE" > /dev/null
    sudo chmod 644 "$CONFIG_SYSTEM_FILE"
}

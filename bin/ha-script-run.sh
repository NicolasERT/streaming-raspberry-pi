#!/usr/bin/env bash
# ==============================================================================
# ha-script-run.sh — Wrapper para ejecutar scripts/escenas de Home Assistant.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_TAG="HA-WRAPPER"

source "$SCRIPT_DIR/../config/config.sh"
load_config

MAX_RETRIES=3
RETRY_DELAY=2

usage() {
    cat <<EOF
Uso: $(basename "$0") <entity_id>

Ejemplo:
  $(basename "$0") script.subir_canal
  $(basename "$0") scene.noche
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
    log_error "Debes indicar un entity_id (ej. script.subir_canal o scene.noche)."
    usage >&2
    exit 1
fi

require_cmd curl || exit 1

if [ ! -f "$HA_TOKEN_FILE" ]; then
    log_error "No existe $HA_TOKEN_FILE. Configura primero el token de Home Assistant."
    exit 1
fi

ENTITY_ID="$1"
TOKEN="$(tr -d '\r\n' < "$HA_TOKEN_FILE")"

DOMAIN="${ENTITY_ID%%.*}"

if [ "$DOMAIN" != "script" ] && [ "$DOMAIN" != "scene" ]; then
    log_error "Solo se admiten entity_id de tipo script.* o scene.*"
    exit 1
fi

if [ -z "$TOKEN" ]; then
    log_error "El token en $HA_TOKEN_FILE está vacío."
    exit 1
fi

PAYLOAD="{\"entity_id\":\"$ENTITY_ID\"}"
URL="$HA_BASE_URL/api/services/$DOMAIN/turn_on"

attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
    attempt=$((attempt + 1))

    if curl -sS -f \
        --connect-timeout 10 \
        --max-time 30 \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$URL" \
        >/dev/null 2>&1; then
        log_info "OK: ejecutado $ENTITY_ID en Home Assistant"
        exit 0
    fi

    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        log_warn "Intento $attempt/$MAX_RETRIES fallido para $ENTITY_ID. Reintentando en ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))
    fi
done

log_error "Fallo tras $MAX_RETRIES intentos ejecutando $ENTITY_ID en $HA_BASE_URL"
exit 1

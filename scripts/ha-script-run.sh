#!/usr/bin/env bash
set -euo pipefail

HA_BASE_URL="${HA_BASE_URL:-http://localhost:8123}"
TOKEN_FILE="/etc/ha-token"

usage() {
  cat <<EOF
Uso: $(basename "$0") <entity_id_script>

Ejemplo:
  $(basename "$0") script.subir_canal
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  echo "Error: Debes indicar un entity_id de script (ej. script.subir_canal)." >&2
  usage >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl no está instalado en el sistema." >&2
  exit 1
fi

if [ ! -f "$TOKEN_FILE" ]; then
  echo "Error: No existe $TOKEN_FILE. Configura primero el token de Home Assistant." >&2
  exit 1
fi

SCRIPT_ID="$1"
TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"

if [ -z "$TOKEN" ]; then
  echo "Error: El token en $TOKEN_FILE está vacío." >&2
  exit 1
fi

PAYLOAD="{\"entity_id\":\"$SCRIPT_ID\"}"

curl -sS -f \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$HA_BASE_URL/api/services/script/turn_on" \
  >/dev/null

echo "OK: ejecutado $SCRIPT_ID en Home Assistant"

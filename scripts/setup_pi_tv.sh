#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_USER="$(id -un)"
DEFAULT_PLUGIN_SRC="$ROOT_DIR/cockpit/pi-tv"
DEFAULT_COCKPIT_DIR="$HOME/.local/share/cockpit/pi-tv"

PI_USER="$DEFAULT_USER"
PLUGIN_SRC="$DEFAULT_PLUGIN_SRC"
COCKPIT_DIR="$DEFAULT_COCKPIT_DIR"
SIZE="1920x1080"
FPS="60"
TEMP_LIMIT="75"
RTMP_URL=""
VIDEO_DEVICE=""

usage() {
  cat <<EOF
Uso: $(basename "$0") [opciones]

Opciones:
  -u <usuario>       Usuario para install.sh (default: $DEFAULT_USER)
  -p <directorio>    Ruta del plugin Cockpit fuente (default: $DEFAULT_PLUGIN_SRC)
  -c <directorio>    Carpeta final del plugin Cockpit (default: $DEFAULT_COCKPIT_DIR)
  -s <resolución>    Resolución inicial (default: 1920x1080)
  -f <fps>           FPS inicial (default: 60)
  -T <temperatura>   Límite térmico CPU (default: 75)
  -r <rtmp_url>      URL RTMP para install.sh (opcional)
  -v <video_dev>     Dispositivo de video para install.sh, ej /dev/video0 (opcional)
  -h                 Mostrar ayuda
EOF
}

while getopts ":u:p:c:s:f:T:r:v:h" opt; do
  case "$opt" in
    u) PI_USER="$OPTARG" ;;
    p) PLUGIN_SRC="$OPTARG" ;;
    c) COCKPIT_DIR="$OPTARG" ;;
    s) SIZE="$OPTARG" ;;
    f) FPS="$OPTARG" ;;
    T) TEMP_LIMIT="$OPTARG" ;;
    r) RTMP_URL="$OPTARG" ;;
    v) VIDEO_DEVICE="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Falta valor para -$OPTARG" >&2
      exit 1
      ;;
    \?)
      echo "Opción inválida: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "$ROOT_DIR/install.sh" ]; then
  echo "No se encontró install.sh en: $ROOT_DIR" >&2
  exit 1
fi

if [ ! -d "$PLUGIN_SRC" ]; then
  echo "No existe la carpeta del plugin: $PLUGIN_SRC" >&2
  exit 1
fi

echo "==> [1/4] Copiando plugin Cockpit a: $COCKPIT_DIR"
mkdir -p "$COCKPIT_DIR"
cp "$PLUGIN_SRC/manifest.json" "$COCKPIT_DIR/manifest.json"
cp "$PLUGIN_SRC/index.html" "$COCKPIT_DIR/index.html"
cp "$PLUGIN_SRC/app.js" "$COCKPIT_DIR/app.js"
cp "$PLUGIN_SRC/app.css" "$COCKPIT_DIR/app.css"

echo "==> [2/4] Ejecutando install.sh de streaming-raspberry-pi"
chmod +x "$ROOT_DIR/install.sh"
INSTALL_ARGS=( -u "$PI_USER" -s "$SIZE" -f "$FPS" -T "$TEMP_LIMIT" )
if [ -n "$RTMP_URL" ]; then
  INSTALL_ARGS+=( -r "$RTMP_URL" )
fi
if [ -n "$VIDEO_DEVICE" ]; then
  INSTALL_ARGS+=( -v "$VIDEO_DEVICE" )
fi
(
  cd "$ROOT_DIR"
  ./install.sh "${INSTALL_ARGS[@]}"
)

echo "==> [3/4] Recargando servicios"
sudo systemctl daemon-reload
sudo systemctl restart streaming-tv.service || true
sudo systemctl restart cockpit || true

echo "==> [4/4] Estado final"
sudo systemctl --no-pager --full status streaming-tv.service | head -n 20 || true

echo
echo "✅ Configuración finalizada"
echo "- Plugin Cockpit: $COCKPIT_DIR"
echo "- Servicio: streaming-tv.service"

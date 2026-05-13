#!/bin/bash

# ==============================================================================
# VDO.Ninja Publisher via WHIP
# Lee el stream RTSP de MediaMTX y lo publica a VDO.Ninja.
# PASSWORD se inyecta como variable de entorno desde /etc/vdoninja.conf
# mediante EnvironmentFile en el servicio systemd.
# ==============================================================================

VDONINJA_SESSION_DIR="/run/vdoninja-publisher"
VDONINJA_SESSION="$VDONINJA_SESSION_DIR/session.conf"
RTSP_URL="rtsp://localhost:8554/live/stream"
WHIP_BASE="https://whip.vdo.ninja"

# ==============================================================================
# VALIDACIÓN DE DEPENDENCIAS
# ==============================================================================
if ! ffmpeg -formats 2>/dev/null | grep -q 'whip'; then
    echo "❌ FFmpeg no incluye soporte WHIP (requiere FFmpeg 6.1+)."
    echo "   Instala jellyfin-ffmpeg u otra versión actualizada:"
    echo "   https://github.com/jellyfin/jellyfin-ffmpeg/releases"
    exit 1
fi

# ==============================================================================
# PREPARACIÓN
# ==============================================================================
# PASSWORD viene de EnvironmentFile=/etc/vdoninja.conf vía systemd
if [ -z "${PASSWORD:-}" ]; then
    echo "⚠️ PASSWORD no definido. Verifica /etc/vdoninja.conf"
fi

# Generar Stream ID único para esta sesión
STREAM_ID=$(openssl rand -hex 6)

# Asegurar que el directorio de sesión existe (creado por RuntimeDirectory en el servicio)
mkdir -p "$VDONINJA_SESSION_DIR"

# Escribir la información de sesión para que Cockpit la consulte
printf 'STREAM_ID=%s\n' "$STREAM_ID" > "$VDONINJA_SESSION"
chmod 644 "$VDONINJA_SESSION"

# Construir URLs
WHIP_URL="${WHIP_BASE}/?push=${STREAM_ID}"
VIEWER_URL="https://vdo.ninja/?view=${STREAM_ID}"
if [ -n "${PASSWORD:-}" ]; then
    WHIP_URL="${WHIP_URL}&password=${PASSWORD}"
    VIEWER_URL="${VIEWER_URL}&password=${PASSWORD}"
fi

echo "🎥 VDO.Ninja Stream ID: $STREAM_ID"
echo "🔗 URL Viewer: $VIEWER_URL"

# ==============================================================================
# LIMPIEZA AL SALIR
# ==============================================================================
cleanup() {
    echo "🛑 Deteniendo VDO.Ninja publisher..."
    rm -f "$VDONINJA_SESSION"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# ==============================================================================
# PUBLICACIÓN VÍA WHIP
# ==============================================================================
echo "📡 Publicando a VDO.Ninja vía WHIP..."
ffmpeg -loglevel warning \
    -rtsp_transport tcp \
    -i "$RTSP_URL" \
    -c:v copy \
    -c:a libopus -b:a 96k -ar 48000 -ac 1 \
    -f whip "$WHIP_URL"

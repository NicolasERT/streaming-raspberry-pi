#!/bin/bash

# --- CONFIGURACIÓN ---
USER_NAME="nicolasrt"
INSTALL_DIR="/home/$USER_NAME"
REPO_DIR=$(pwd) # Asume que ejecutas el script desde la carpeta del repo clonado

echo "🚀 Iniciando despliegue del sistema desde archivos del repositorio..."

# 1. Instalar dependencias necesarias
echo "📦 Instalando herramientas de sistema..."
sudo apt update && sudo apt install -y ffmpeg v4l-utils alsa-utils cockpit docker.io docker-compose

# 2. Configurar permisos de usuario
sudo usermod -aG docker $USER_NAME

# 3. Copiar y preparar el Script de Bash
echo "📜 Configurando script de ejecución..."
if [ -f "$REPO_DIR/streaming-tv.sh" ]; then
    cp "$REPO_DIR/streaming-tv.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/streaming-tv.sh"
    chown $USER_NAME:$USER_NAME "$INSTALL_DIR/streaming-tv.sh"
else
    echo "❌ Error: No se encontró streaming-tv.sh en el repositorio."
fi

# 4. Copiar y preparar el Docker Compose
echo "🐳 Configurando MediaMTX..."
if [ -f "$REPO_DIR/docker-compose.yml" ]; then
    cp "$REPO_DIR/docker-compose.yml" "$INSTALL_DIR/"
    chown $USER_NAME:$USER_NAME "$INSTALL_DIR/docker-compose.yml"
    # Levantar el contenedor
    cd "$INSTALL_DIR" && sudo docker-compose up -d
    cd "$REPO_DIR"
else
    echo "❌ Error: No se encontró docker-compose.yml."
fi

# 5. Instalar el Servicio de Systemd
echo "⚙️ Instalando servicio de sistema..."
if [ -f "$REPO_DIR/streaming-tv.service" ]; then
    sudo cp "$REPO_DIR/streaming-tv.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable streaming-tv.service
    echo "✅ Servicio habilitado correctamente."
else
    echo "❌ Error: No se encontró streaming-tv.service."
fi

echo "---"
echo "✅ Despliegue finalizado."
echo "Puedes controlar el stream desde Cockpit o con: sudo systemctl start streaming-tv"

# 📹 Sistema de Streaming TV — Raspberry Pi 5

Captura video y audio desde una cámara USB 3.0 en una **Raspberry Pi 5** y transmite a la red local vía **RTMP**, con visualización por **WebRTC**, **HLS**, **RTSP** o **VLC**.

---

## ⚙️ Arquitectura

| Componente | Función |
|------------|---------|
| **FFmpeg** | Captura V4L2 + ALSA, codifica H.264/AAC, envía flujo RTMP |
| **MediaMTX** | Media proxy (RTMP → WebRTC / HLS / RTSP) en Docker |
| **Cockpit** | Interfaz web para controlar servicios y ver el stream |
| **systemd** | Servicios para streaming, monitor térmico y monitor de inactividad |

---

## 📁 Estructura del Repositorio

```
streaming-raspberry-pi/
├── install.sh                      # Instalador interactivo (TUI)
├── README.md
├── docker-compose.yml              # MediaMTX container
├── config/
│   ├── default.env                 # Parámetros por defecto (centralizados)
│   └── config.sh                   # Librería helper compartida
├── systemd/
│   ├── streaming-tv.service        # Plantilla servicio streaming
│   ├── thermal-monitor.service     # Plantilla monitor térmico
│   └── idle-monitor.service        # Plantilla monitor inactividad
├── bin/
│   ├── streaming-tv.sh             # Captura y transmisión FFmpeg
│   ├── thermal-monitor.sh          # Centinela de temperatura CPU
│   ├── idle-monitor.sh             # Apagado por inactividad
│   └── ha-script-run.sh            # Wrapper Home Assistant
└── cockpit/
    └── pi-tv/                      # Plugin Cockpit (UI web)
        ├── manifest.json
        ├── index.html
        ├── app.js
        └── app.css
```

---

## 🚀 Instalación

### Modo interactivo (recomendado)

```bash
chmod +x install.sh
./install.sh
```

Se abrirá un asistente con `whiptail` donde podrás:

1. **Seleccionar componentes** a instalar (dependencias, MediaMTX, streaming, monitor térmico, monitor de inactividad, Cockpit, Home Assistant)
2. **Configurar parámetros** de cada componente (resolución, FPS, bitrate, puertos, temperatura, etc.)
3. **Revisar** la configuración antes de aplicarla
4. **Ejecutar** la instalación con barra de progreso

### Modo no-interactivo

```bash
./install.sh --non-interactive -u nicolasrt -s 1280x720 -f 30 -T 70
```

Usa los valores de `config/default.env` con overrides por CLI:

| Flag | Descripción | Default |
|------|-------------|---------|
| `-u` | Usuario del sistema | nicolasrt |
| `-s` | Resolución de video | 1920x1080 |
| `-f` | FPS | 60 |
| `-r` | URL RTMP | rtmp://localhost:1935/live/stream |
| `-v` | Dispositivo de video | /dev/video0 |
| `-b` | Bus USB (Bus-Puerto) | 5-1 |
| `-T` | Límite de temperatura (°C) | 75 |
| `-H` | Token de Home Assistant | (vacío) |
| `-n` | Nombre dispositivo audio | USB3.0 Video |

---

## 🔧 Configuración

Toda la configuración está centralizada en un solo archivo:

- **Defaults del repo**: [`config/default.env`](config/default.env) — plantilla con valores por defecto
- **Config del sistema**: `/etc/streaming-pi/config.env` — generado por el instalador, sobreescribe defaults
- **Config Cockpit**: `/etc/streaming-pi/cockpit-config.json` — puertos y entidades HA para el plugin web

### Parámetros configurables

| Categoría | Parámetro | Default | Descripción |
|-----------|-----------|---------|-------------|
| **Video** | `V_DEV` | /dev/video0 | Dispositivo de video |
| | `SIZE` | 1920x1080 | Resolución |
| | `FPS` | 60 | Fotogramas por segundo |
| | `VIDEO_BITRATE` | 4000k | Bitrate de video |
| **Audio** | `DEV_NAME` | USB3.0 Video | Nombre dispositivo ALSA |
| | `AUDIO_SAMPLE_RATE` | 44100 | Sample rate (Hz) |
| | `AUDIO_VOLUME` | 15 | Volumen (dB) |
| **USB** | `U_BUS` | 5-1 | Bus USB para reset eléctrico |
| **RTMP** | `RTMP_URL` | rtmp://localhost:1935/live/stream | URL servidor RTMP |
| **MediaMTX** | `RTMP_PORT` | 1935 | Puerto RTMP |
| | `HLS_PORT` | 8888 | Puerto HLS |
| | `WEBRTC_PORT` | 8889 | Puerto WebRTC |
| | `RTSP_PORT` | 8554 | Puerto RTSP |
| **Térmico** | `TEMP_LIMIT` | 75 | Límite temperatura CPU (°C) |
| | `THERMAL_CHECK_INTERVAL` | 10 | Intervalo chequeo (seg) |
| | `THERMAL_COOLDOWN` | 60 | Enfriamiento post-alerta (seg) |
| **Inactividad** | `IDLE_TIME` | 300 | Tiempo sin espectadores (seg) |
| | `IDLE_CHECK_INTERVAL` | 30 | Intervalo chequeo (seg) |
| **Home Assistant** | `HA_BASE_URL` | http://localhost:8123 | URL de HA |
| | `HA_TOKEN_FILE` | /etc/ha-token | Ruta del token |
| | `HA_ENTITIES` | (escenas TV) | Entidades HA configurables |

---

## 🛠️ Componentes

### `bin/streaming-tv.sh`

Realiza el mantenimiento del hardware (reset USB), detecta el audio ALSA y lanza la codificación FFmpeg vía RTMP.

### `bin/thermal-monitor.sh`

Centinela de temperatura CPU. Detiene el streaming si supera el límite configurado. Incluye histéresis térmica para evitar reinicios en ráfaga.

### `bin/idle-monitor.sh`

Monitorea conexiones activas en los puertos de MediaMTX. Si no detecta espectadores durante el tiempo configurado, detiene el servicio de streaming.

### `bin/ha-script-run.sh`

Wrapper para ejecutar scripts y escenas de Home Assistant. Incluye reintentos automáticos con backoff exponencial.

### `cockpit/pi-tv/`

Plugin Cockpit con interfaz web para:
- Iniciar/Detener el streaming
- Cambiar resolución en caliente
- Controlar TV vía Home Assistant (entidades configurables)
- Ver stream embebido (WebRTC/HLS)

---

## 📱 Acceso

| Función | URL |
|---------|-----|
| Control On/Off | `https://<IP>:9090` (Cockpit) |
| Ver en Web (WebRTC) | `http://<IP>:8889/live/stream` |
| Ver en Web (HLS) | `http://<IP>:8888/live/stream` |
| Ver en VLC | `rtmp://<IP>:1935/live/stream` |
| Ver en ffplay | `ffplay -i "rtmp://<IP>:1935/live/stream" -fflags nobuffer` |

---

## 🔍 Gestión y Diagnóstico

```bash
# Ver logs en tiempo real
journalctl -u streaming-tv.service -f

# Reiniciar streaming
sudo systemctl restart streaming-tv.service

# Estado de MediaMTX
sudo docker ps

# Diagnóstico de hardware
v4l2-ctl --list-devices
arecord -l

# Ver configuración activa
cat /etc/streaming-pi/config.env
```

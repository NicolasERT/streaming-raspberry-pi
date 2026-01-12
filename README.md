# 📹 Sistema de Streaming TV (NicolasRT)

Este proyecto permite capturar video y audio de una cámara USB 3.0 en una Raspberry Pi 5 y transmitirlo a la red local mediante RTMP, permitiendo visualización en navegadores (WebRTC), VLC u OBS.

## ⚙️ Descripción Técnica de Software

El ecosistema se apoya en tres pilares de software de alto rendimiento para garantizar estabilidad y baja latencia:

*   **[FFmpeg](ffmpeg.org):** Es el motor de procesamiento multimedia. Se encarga de capturar el video crudo desde la cámara (`V4L2`) y el audio desde el micrófono (`ALSA`), comprimirlos usando el códec H.264 (video) y AAC (audio), y empaquetarlos en un flujo RTMP en tiempo real.
*   **[MediaMTX](github.com):** Un servidor de medios (media proxy) de alto rendimiento escrito en Go. Actúa como el receptor central de la señal; permite que un solo flujo de entrada sea consumido simultáneamente por múltiples clientes a través de diversos protocolos como WebRTC, HLS y RTSP sin necesidad de recodificar.
*   **[Cockpit](cockpit-project.org):** Una interfaz gráfica basada en web para servidores Linux. Proporciona una capa de abstracción sobre `systemd`, permitiendo que el usuario inicie, detenga o monitoree los logs del servicio `streaming-tv` de forma visual y segura desde cualquier navegador, eliminando la necesidad de comandos manuales por SSH.

## 🚀 Instalación y Despliegue Personalizado

El script `install.sh` ahora permite configurar todo el sistema en un solo comando mediante parámetros nombrados. Si no se pasan parámetros, el sistema usará los valores por defecto (RTMP, nicolasrt, USB3.0 Video).

### Comando de instalación
```bash
# Uso básico (Valores por defecto)
chmod +x install.sh && ./install.sh

# Uso avanzado (Personalizado)
./install.sh -u nicolasrt -m RTMP -n "USB3.0 Video" -v /dev/video0 -b 5-1
```

### Parámetros Disponibles
| Flag | Descripción | Valor por defecto |
| - | - | - |
| -u	| Usuario del sistema que ejecutará el servicio	| nicolasrt |
| -m	| Modo de transmisión (RTMP o UDP) | RTMP |
| -n	| Nombre del dispositivo de audio (ALSA)	| USB3.0 Video |
| -i	| IP de destino (Solo necesario para modo UDP)	| 192.168.68.56 |
| -r	| URL del servidor RTMP	| rtmp://127.0.0.1:1935/live/stream |
| -v	| Ruta del dispositivo de video	| /dev/video0 |
| -b	| Identificador del Bus USB para reset (Bus-Puerto)	| 5-1 |
| -s	| Resolución	| 1920x1080 |
| -f	| Framerate	| 60 |


## 🛠️ Componentes Incluidos

El sistema se basa en cuatro archivos principales que trabajan en conjunto para garantizar la estabilidad de la transmisión:

*   **`streaming-tv.sh`**: Script de Bash que realiza el mantenimiento del hardware (reset del bus USB 3.0), detecta dinámicamente la tarjeta de sonido y lanza el proceso de codificación con FFmpeg.
*   **`streaming-tv.service`**: Unidad de configuración para `systemd`. Permite que el streaming funcione como un servicio del sistema, facilitando su gestión (encendido/apagado) desde paneles externos como Cockpit.
*   **`docker-compose.yml`**: Define el contenedor de **MediaMTX**. Actúa como el servidor de medios que recibe la señal RTMP y la convierte automáticamente a WebRTC y HLS para su visualización en navegadores.
*   **`install.sh`**: Script de automatización que instala todas las dependencias necesarias, configura los permisos de Docker y despliega los archivos anteriores en sus rutas correctas.

## 📱 Control y Visualización

| Función	Dirección | URL |
|--------------|--------------|
| Control On/Off | https://IP_DE_LA_PI:9090 (Panel Cockpit) |
| Ver en Web | http://IP_DE_LA_PI:8888/live/stream |
| Ver en VLC | rtmp://IP_DE_LA_PI:1935/live/stream |

## 🔧 Gestión del Sistema
Para el mantenimiento y monitoreo del servicio a través de la terminal, utiliza los siguientes comandos:

* Ver logs en tiempo real:
```bash
journalctl -u streaming-tv.service -f
```

* Reiniciar manualmente el stream:
```bash
sudo systemctl restart streaming-tv.service
```

* Detener la transmisión:
```bash
sudo systemctl stop streaming-tv.service
```

* Verificar estado de los contenedores (MediaMTX):
```bash
sudo docker ps
```

* Diagnóstico de hardware (Cámara y Audio):
```bash
v4l2-ctl --list-devices
arecord -l
```

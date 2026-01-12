# 📹 Sistema de Streaming TV (NicolasRT)

Este proyecto permite capturar video y audio de una cámara USB 3.0 en una **Raspberry Pi 5** y transmitirlo a la red local mediante **RTMP**, permitiendo visualización en navegadores (**WebRTC**), **VLC** u **OBS**.

---

## ⚙️ Descripción Técnica de Software

El ecosistema se apoya en tres pilares de software de alto rendimiento para garantizar estabilidad y baja latencia:

- **FFmpeg (ffmpeg.org)**  
  Motor de procesamiento multimedia. Se encarga de capturar video crudo (V4L2) y audio (ALSA), comprimirlos en H.264/AAC y empaquetarlos en flujo RTMP.

- **MediaMTX (github.com)**  
  Servidor de medios (media proxy) que actúa como receptor central; permite que el flujo sea consumido simultáneamente vía WebRTC, HLS y RTSP.

- **Cockpit (cockpit-project.org)**  
  Interfaz gráfica web para Linux. Permite gestionar los servicios de systemd (iniciar/detener) y monitorear logs de forma visual sin usar SSH.

---

## 🚀 Instalación y Despliegue Personalizado

El script install.sh permite configurar el sistema en un solo comando.  
Si no se pasan parámetros, usará los valores por defecto (RTMP, nicolasrt, 1080p@60fps).

---

## 💻  Comando de instalación

### Uso básico (valores por defecto)
```bash
chmod +x install.sh && ./install.sh
```

### Uso avanzado  
Ejemplo: 720p a 30fps con límite térmico de 70°C
```bash
./install.sh -u nicolasrt -s 1280x720 -f 30 -T 70
```

---

## 📊 Parámetros Disponibles

| Flag | Descripción | Valor por defecto |
|----|------------|------------------|
| -u | Usuario del sistema que ejecutará el servicio | nicolasrt |
| -m | Modo de transmisión (RTMP o UDP) | RTMP |
| -n | Nombre del dispositivo de audio (ALSA) | USB3.0 Video |
| -i | IP de destino (solo para modo UDP) | 192.168.68.56 |
| -r | URL del servidor RTMP local | rtmp://127.0.0.1:1935/live/stream |
| -v | Ruta del dispositivo de video | /dev/video0 |
| -b | ID del Bus USB para reset (Bus-Puerto) | 5-1 |
| -s | Resolución de video (Ancho x Alto) | 1920x1080 |
| -f | Cuadros por segundo (FPS) | 60 |
| -T | Límite de temperatura de CPU (°C) | 75 |
| -I | Tiempo de inactividad (segundos) para apagar el stream | 300 |
| -S | Servicio a detener si hay sobrecalentamiento o inactividad | streaming-tv.service |
| -p | Ruta del stream en MediaMTX que el monitor vigilará | live/stream |
| -c | Intervalo en segundos entre cada comprobación de espectadores | 30 |

---

## 🛠️ Componentes Incluidos

- **streaming-tv.sh**  
  Realiza el mantenimiento del hardware (reset USB), detecta el audio y lanza la codificación FFmpeg.

- **streaming-tv.service**  
  Permite la gestión del stream como servicio de sistema desde Cockpit.

- **thermal-monitor.sh**  
  Script centinela que supervisa la temperatura y detiene el stream en caso de calor crítico.

- **thermal-monitor.service**  
  Mantiene el monitoreo térmico activo en segundo plano desde el arranque.

- **idle-monitor.sh** 
  Script de eficiencia energética que consulta la API de MediaMTX. Si no detecta espectadores durante un tiempo determinado (parámetro -t), ordena el apagado automático del streaming.

- **idle-monitor.service** 
Servicio encargado de mantener la vigilancia de inactividad activa en segundo plano.

- **docker-compose.yml**  
  Define el contenedor MediaMTX para la distribución del flujo de video.

- **install.sh**  
  Automatiza dependencias, permisos y despliega los archivos en sus rutas correctas.

---

## 📱 Control y Visualización

| Función | Método / URL |
|-------|--------------|
| Control On/Off | Cockpit en https://IP_DE_LA_PI:9090 |
| Ver en Web | http://IP_DE_LA_PI:8889/live/stream (WebRTC) |
| Ver en VLC | rtmp://IP_DE_LA_PI:1935/live/stream |
| Ver en ffplay | ffplay -i "rtmp://IP_DE_LA_PI:1935/live/stream" -fflags nobuffer |

---

## 🔧 Gestión del Sistema

### Ver logs en tiempo real
```bash
journalctl -u streaming-tv.service -f
```

### Reiniciar manualmente el stream
```bash
sudo systemctl restart streaming-tv.service
```

### Verificar estado de MediaMTX
```bash
sudo docker ps
```

### Diagnóstico de hardware
```bash
v4l2-ctl --list-devices y arecord -l
```

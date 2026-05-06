const SERVICE_NAME = "streaming-tv.service";
const SERVICE_FILE = "/etc/systemd/system/streaming-tv.service";
const HA_WRAPPER = "/usr/local/bin/ha-script-run.sh";
const STREAM_PORT = "8888";

const RESOLUTION_PRESETS = {
  "1920x1080|60": { size: "1920x1080", fps: "60", label: "1080p" },
  "1280x720|30": { size: "1280x720", fps: "30", label: "720p" },
  "854x480|30": { size: "854x480", fps: "30", label: "480p" }
};

const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const message = document.getElementById("message");
const streamFrame = document.getElementById("stream-frame");

const controlsPanel = document.getElementById("controls-panel");
const btnStart = document.getElementById("btn-start");
const btnStop = document.getElementById("btn-stop");
const resolutionSelect = document.getElementById("resolution-select");

const funnelStatusDot = document.getElementById("funnel-status-dot");
const funnelStatusText = document.getElementById("funnel-status-text");
const funnelUrl = document.getElementById("funnel-url");
const funnelToggleBtn = document.getElementById("funnel-toggle-btn");

let funnelActive = false;

const sceneButtons = [
  { id: "btn-ch-up", entityId: "scene.subir_canal_tv", label: "Subir canal" },
  { id: "btn-ch-down", entityId: "scene.bajar_canal_tv", label: "Bajar canal" },
  { id: "btn-scene-up", entityId: "scene.arriba_tv", label: "Arriba" },
  { id: "btn-scene-down", entityId: "scene.abajo_tv", label: "Abajo" },
  { id: "btn-scene-left", entityId: "scene.izquierda_tv", label: "Izquierda" },
  { id: "btn-scene-right", entityId: "scene.derecha_tv", label: "Derecha" },
  { id: "btn-scene-guide", entityId: "scene.guia_tv", label: "Guia" },
  { id: "btn-scene-ok", entityId: "scene.ok_tv", label: "OK" },
  { id: "btn-scene-language", entityId: "scene.idioma_tv", label: "Idioma" },
  { id: "btn-scene-subtitle", entityId: "scene.subtitulos_tv", label: "Subtitulo" }
];

const sceneElements = sceneButtons
  .map((item) => ({ ...item, element: document.getElementById(item.id) }))
  .filter((item) => item.element);

const allControls = [btnStart, btnStop, resolutionSelect, funnelToggleBtn, ...sceneElements.map((item) => item.element)];

function setActionButtonsVisibility(state) {
  const isActive = state === "active";

  btnStart.style.display = isActive ? "none" : "";
  btnStop.style.display = isActive ? "" : "none";
}

function getStreamHost() {
  const params = new URLSearchParams(window.location.search);
  const hostParam = params.get("streamHost");

  if (hostParam && hostParam.trim()) {
    return hostParam.trim();
  }

  return window.location.hostname || "localhost";
}

function getStreamUrl() {
  return `http://${getStreamHost()}:${STREAM_PORT}/live/stream?muted=false`;
}

function setBusy(isBusy) {
  allControls.forEach((control) => {
    control.disabled = isBusy;
  });
}

function setMessage(text, type = "info") {
  message.textContent = text;
  message.className = `message is-${type}`;
}

function setServiceState(state) {
  statusDot.className = "status-dot";

  if (state === "active") {
    statusDot.classList.add("is-active");
    statusText.textContent = "Estado: activo";
    return;
  }

  if (state === "inactive") {
    statusDot.classList.add("is-inactive");
    statusText.textContent = "Estado: detenido";
    return;
  }

  statusDot.classList.add("is-unknown");
  statusText.textContent = "Estado: desconocido";
}

function refreshFrame() {
  const src = streamFrame.getAttribute("src") || getStreamUrl();
  streamFrame.setAttribute("src", src);
}

function parseError(error) {
  if (!error) {
    return "Error desconocido";
  }

  if (error.problem) {
    return `${error.problem}${error.message ? `: ${error.message}` : ""}`;
  }

  if (error.message) {
    return error.message;
  }

  return String(error);
}

function checkStatus() {
  return cockpit
    .spawn(["systemctl", "is-active", SERVICE_NAME], { err: "ignore" })
    .then((output) => {
      const state = output.trim();
      setServiceState(state);
      setActionButtonsVisibility(state);
      return state;
    })
    .catch(() => {
      setServiceState("unknown");
      setActionButtonsVisibility("unknown");
      return "unknown";
    });
}

function checkFunnelStatus() {
  return cockpit
    .spawn(["sudo", "tailscale", "funnel", "status"], { superuser: "require", err: "ignore" })
    .then((output) => {
      const isActive = output.includes(STREAM_PORT);
      funnelActive = isActive;
      funnelStatusDot.className = "status-dot " + (isActive ? "is-active" : "is-inactive");
      funnelStatusText.textContent = isActive ? "Activo" : "Inactivo";
      funnelToggleBtn.disabled = false;
      funnelToggleBtn.textContent = isActive ? "Detener exposición" : "Exponer por Tailscale";

      if (isActive) {
        const baseMatch = output.match(/^(https:\/\/[^\s\/]+)/m);
        if (baseMatch) {
          const streamUrl = baseMatch[1] + "/live/stream/?muted=false";
          funnelUrl.textContent = streamUrl;
          funnelUrl.href = streamUrl;
          funnelUrl.style.display = "";
        } else {
          funnelUrl.style.display = "none";
        }
      } else {
        funnelUrl.style.display = "none";
      }
    })
    .catch(() => {
      funnelActive = false;
      funnelStatusDot.className = "status-dot is-unknown";
      funnelStatusText.textContent = "No disponible";
      funnelToggleBtn.disabled = true;
      funnelToggleBtn.textContent = "Exponer por Tailscale";
      funnelUrl.style.display = "none";
    });
}

function toggleFunnel() {
  const wasActive = funnelActive;
  setBusy(true);
  setMessage(wasActive ? "Deteniendo exposición..." : "Activando Tailscale Funnel...", "muted");

  const args = wasActive
    ? ["sudo", "tailscale", "funnel", "off"]
    : ["sudo", "tailscale", "funnel", "--bg", STREAM_PORT];

  return cockpit
    .spawn(args, { superuser: "require", err: "message" })
    .then(() => {
      setMessage(
        wasActive ? "Exposición detenida" : `Puerto ${STREAM_PORT} expuesto por Tailscale`,
        "success"
      );
    })
    .catch((error) => {
      setMessage(`Error: ${parseError(error)}`, "error");
    })
    .finally(() => {
      setBusy(false);
      checkFunnelStatus();
    });
}

function resolutionReadScript() {
  return `
set -eu

if ! test -f "${SERVICE_FILE}"; then
  exit 0
fi

size="$(grep -oE -- '-s [0-9]+x[0-9]+' "${SERVICE_FILE}" | head -n 1 | awk '{print $2}')"
fps="$(grep -oE -- '-f [0-9]+' "${SERVICE_FILE}" | head -n 1 | awk '{print $2}')"

if [ -n "$size" ] && [ -n "$fps" ]; then
  printf '%s|%s\n' "$size" "$fps"
fi
`;
}

function applyCurrentResolutionSelection() {
  return cockpit
    .script(resolutionReadScript(), [], { superuser: "require", err: "message" })
    .then((output) => {
      const value = output.trim();
      if (!value) {
        return;
      }

      const knownPreset = RESOLUTION_PRESETS[value];
      if (!knownPreset && !Array.from(resolutionSelect.options).some((option) => option.value === value)) {
        const [size, fps] = value.split("|");
        const option = document.createElement("option");
        option.value = value;
        option.textContent = `${size} @ ${fps} FPS (actual)`;
        resolutionSelect.appendChild(option);
      }

      resolutionSelect.value = value;
    })
    .catch(() => {
      // Si no se puede leer el service file, mantenemos la selección por defecto.
    });
}

function runCommand(args, successText) {
  setBusy(true);
  setMessage("Procesando...", "muted");

  return cockpit
    .spawn(args, { superuser: "require", err: "message" })
    .then(() => {
      setMessage(successText, "success");
    })
    .catch((error) => {
      setMessage(`Error: ${parseError(error)}`, "error");
      throw error;
    })
    .finally(() => {
      setBusy(false);
      checkStatus();
    });
}

function resolutionScript(size, fps) {
  return `
set -eu

if ! test -f "${SERVICE_FILE}"; then
  echo "No existe ${SERVICE_FILE}" >&2
  exit 1
fi

sed -E -i 's/-s [0-9]+x[0-9]+/-s ${size}/g' "${SERVICE_FILE}"
sed -E -i 's/-f [0-9]+/-f ${fps}/g' "${SERVICE_FILE}"

systemctl daemon-reload
systemctl restart ${SERVICE_NAME}
`;
}

function runResolution(size, fps) {
  setBusy(true);
  setMessage(`Aplicando ${size} a ${fps} FPS...`, "muted");

  return cockpit
    .script(resolutionScript(size, fps), [], { superuser: "require", err: "message" })
    .then(() => {
      setMessage(`Resolución aplicada: ${size} @ ${fps} FPS`, "success");
      refreshFrame();
    })
    .catch((error) => {
      setMessage(`Error: ${parseError(error)}`, "error");
      throw error;
    })
    .finally(() => {
      setBusy(false);
      checkStatus();
    });
}

function runHomeAssistantAction(entityId, label) {
  setBusy(true);
  setMessage(`Ejecutando ${label}...`, "muted");

  return cockpit
    .spawn([HA_WRAPPER, entityId], { superuser: "require", err: "message" })
    .then(() => {
      setMessage(`${label} ejecutado`, "success");
    })
    .catch((error) => {
      setMessage(`Error: ${parseError(error)}`, "error");
      throw error;
    })
    .finally(() => {
      setBusy(false);
      checkStatus();
    });
}

function initEvents() {
  streamFrame.setAttribute("src", getStreamUrl());

  btnStart.addEventListener("click", () => {
    runCommand(["systemctl", "start", SERVICE_NAME], "Servicio iniciado").then(() => {
      refreshFrame();
    }).catch(() => {});
  });

  btnStop.addEventListener("click", () => {
    runCommand(["systemctl", "stop", SERVICE_NAME], "Servicio detenido").catch(() => {});
  });

  resolutionSelect.addEventListener("change", () => {
    const selected = RESOLUTION_PRESETS[resolutionSelect.value];
    if (!selected) {
      setMessage("Resolución inválida", "error");
      return;
    }

    runResolution(selected.size, selected.fps).catch(() => {});
  });

  sceneElements.forEach(({ element, entityId, label }) => {
    element.addEventListener("click", () => {
      runHomeAssistantAction(entityId, label).catch(() => {});
    });
  });

  funnelToggleBtn.addEventListener("click", () => {
    toggleFunnel().catch(() => {});
  });

  cockpit.addEventListener("visibilitychange", () => {
    if (!cockpit.hidden) {
      checkStatus();
      checkFunnelStatus();
    }
  });
}

cockpit
  .init()
  .then(() => {
    initEvents();
    return Promise.all([checkStatus(), applyCurrentResolutionSelection(), checkFunnelStatus()]);
  })
  .then(() => {
    setMessage("Conectado a Cockpit", "muted");
  })
  .catch((error) => {
    setMessage(`No se pudo inicializar Cockpit: ${parseError(error)}`, "error");
    setBusy(true);
  });

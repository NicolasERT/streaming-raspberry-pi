const SERVICE_NAME = "streaming-tv.service";
const SERVICE_FILE = "/etc/systemd/system/streaming-tv.service";
const HA_WRAPPER = "/usr/local/bin/ha-script-run.sh";

const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const message = document.getElementById("message");
const streamFrame = document.getElementById("stream-frame");

const btnStart = document.getElementById("btn-start");
const btnStop = document.getElementById("btn-stop");
const btn1080 = document.getElementById("btn-1080");
const btn720 = document.getElementById("btn-720");
const btnChUp = document.getElementById("btn-ch-up");
const btnChDown = document.getElementById("btn-ch-down");

const allButtons = [btnStart, btnStop, btn1080, btn720, btnChUp, btnChDown];

function setBusy(isBusy) {
  allButtons.forEach((button) => {
    button.disabled = isBusy;
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
  const src = streamFrame.getAttribute("src");
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
      return state;
    })
    .catch(() => {
      setServiceState("unknown");
      return "unknown";
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

function runChannelAction(scriptId, label) {
  setBusy(true);
  setMessage(`Ejecutando ${label}...`, "muted");

  return cockpit
    .spawn([HA_WRAPPER, scriptId], { superuser: "require", err: "message" })
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
  btnStart.addEventListener("click", () => {
    runCommand(["systemctl", "start", SERVICE_NAME], "Servicio iniciado").then(() => {
      refreshFrame();
    }).catch(() => {});
  });

  btnStop.addEventListener("click", () => {
    runCommand(["systemctl", "stop", SERVICE_NAME], "Servicio detenido").catch(() => {});
  });

  btn1080.addEventListener("click", () => {
    runResolution("1920x1080", "60").catch(() => {});
  });

  btn720.addEventListener("click", () => {
    runResolution("1280x720", "30").catch(() => {});
  });

  btnChUp.addEventListener("click", () => {
    runChannelAction("script.subir_canal", "Subir canal").catch(() => {});
  });

  btnChDown.addEventListener("click", () => {
    runChannelAction("script.bajar_canal", "Bajar canal").catch(() => {});
  });

  cockpit.addEventListener("visibilitychange", () => {
    if (cockpit.hidden) {
      streamFrame.setAttribute("src", "about:blank");
      return;
    }

    streamFrame.setAttribute("src", "http://100.73.121.63:8888/live/stream/");
    checkStatus();
  });
}

cockpit
  .init()
  .then(() => {
    initEvents();
    return checkStatus();
  })
  .then(() => {
    setMessage("Conectado a Cockpit", "muted");
  })
  .catch((error) => {
    setMessage(`No se pudo inicializar Cockpit: ${parseError(error)}`, "error");
    setBusy(true);
  });

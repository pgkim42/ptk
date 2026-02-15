const hostEl = document.getElementById("host");
const portsEl = document.getElementById("ports");
const timeoutEl = document.getElementById("timeout");
const autoMonitorEl = document.getElementById("autoMonitor");
const openOnlyEl = document.getElementById("openOnly");
const loadDefaultBtn = document.getElementById("loadDefault");
const scanBtn = document.getElementById("scan");
const resultsEl = document.getElementById("results");

const invoke = window.__TAURI__?.core?.invoke;
const INTERVAL_MS = 3000;
let timerId = null;
let isScanning = false;
const previousState = new Map();
let lastRows = [];

function renderRows(rows) {
  resultsEl.innerHTML = "";

  if (!rows.length) {
    const tr = document.createElement("tr");
    tr.innerHTML = '<td colspan="6">결과가 없습니다.</td>';
    resultsEl.appendChild(tr);
    return;
  }

  rows.forEach((row) => {
    const tr = document.createElement("tr");
    const statusClass = row.open ? "status-open" : "status-closed";
    const statusText = row.open ? "OPEN" : "CLOSED";
    const prev = previousState.get(row.port);
    if (typeof prev === "boolean" && prev !== row.open) {
      tr.classList.add("state-changed");
    }
    previousState.set(row.port, row.open);

    tr.innerHTML = `
      <td>${row.port}</td>
      <td class="${statusClass}">${statusText}</td>
      <td>${row.pid ?? "-"}</td>
      <td>${row.process_name ?? "-"}</td>
      <td>${row.message ?? ""}</td>
      <td></td>
    `;

    const actionTd = tr.lastElementChild;
    if (row.open && row.pid) {
      const btn = document.createElement("button");
      btn.className = "kill-btn";
      btn.type = "button";
      btn.textContent = "종료";
      btn.addEventListener("click", async () => {
        const ok = window.confirm(`PID ${row.pid} (${row.process_name ?? "unknown"}) 프로세스를 종료할까요?`);
        if (!ok) {
          return;
        }

        const kill = await invoke("kill_process_by_pid", { pid: row.pid });
        if (!kill.ok) {
          window.alert(`종료 실패: ${kill.message}`);
        }
        await runScanOnce();
      });
      actionTd.appendChild(btn);
    } else {
      actionTd.textContent = "-";
    }

    resultsEl.appendChild(tr);
  });
}

function renderError(message) {
  renderRows([
    {
      port: "-",
      open: false,
      pid: null,
      process_name: null,
      message,
    },
  ]);
}

function currentVisibleRows() {
  if (openOnlyEl?.checked) {
    return lastRows.filter((row) => row.open);
  }
  return lastRows;
}

function renderCurrentRows() {
  renderRows(currentVisibleRows());
}

async function runScanOnce() {
  if (!invoke) {
    renderError("Tauri runtime not found");
    return;
  }

  if (isScanning) {
    return;
  }

  const host = hostEl.value.trim() || "127.0.0.1";
  const portsExpr = portsEl.value.trim();
  const timeoutMs = Number(timeoutEl.value);

  if (!portsExpr) {
    lastRows = [];
    renderCurrentRows();
    return;
  }

  isScanning = true;
  scanBtn.disabled = true;

  try {
    const rows = await invoke("scan_ports_cmd", {
      host,
      portsExpr,
      timeoutMs: Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : 300,
    });
    lastRows = rows;
    renderCurrentRows();
  } catch (err) {
    renderError(`오류: ${String(err)}`);
  } finally {
    isScanning = false;
    scanBtn.disabled = false;
  }
}

function applyMonitorState() {
  if (timerId) {
    clearInterval(timerId);
    timerId = null;
  }

  if (autoMonitorEl.checked) {
    timerId = setInterval(() => {
      runScanOnce();
    }, INTERVAL_MS);
  }
}

async function loadDefaultProfile() {
  if (!invoke) {
    return;
  }

  try {
    const profile = await invoke("get_default_profile");
    portsEl.value = profile.ports_expr;
  } catch (err) {
    renderError(`기본 포트 로드 실패: ${String(err)}`);
  }
}

scanBtn.addEventListener("click", runScanOnce);
loadDefaultBtn.addEventListener("click", async () => {
  await loadDefaultProfile();
  await runScanOnce();
});
autoMonitorEl.addEventListener("change", applyMonitorState);
openOnlyEl.addEventListener("change", renderCurrentRows);

(async function init() {
  await loadDefaultProfile();
  applyMonitorState();
  await runScanOnce();
})();

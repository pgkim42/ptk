const hostEl = document.getElementById("host");
const portsEl = document.getElementById("ports");
const timeoutEl = document.getElementById("timeout");
const autoMonitorEl = document.getElementById("autoMonitor");
const openOnlyEl = document.getElementById("openOnly");
const killAllowMismatchEl = document.getElementById("killAllowMismatch");
const loadDefaultBtn = document.getElementById("loadDefault");
const scanBtn = document.getElementById("scan");
const resultsEl = document.getElementById("results");

const invoke = window.__TAURI__?.core?.invoke;
const INTERVAL_MS = 3000;
let timerId = null;
let isScanning = false;
const previousState = new Map();
let lastRows = [];

function hasProcessName(row) {
  return typeof row.process_name === "string" && row.process_name.trim().length > 0;
}

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
      const allowMismatch = Boolean(killAllowMismatchEl?.checked);
      const safeNameAvailable = hasProcessName(row);
      if (!safeNameAvailable && !allowMismatch) {
        actionTd.textContent = "차단됨";
        actionTd.classList.add("blocked-cell");
        actionTd.title = "프로세스명을 확인하지 못해 기본 정책상 종료를 차단했습니다.";
        resultsEl.appendChild(tr);
        return;
      }

      const btn = document.createElement("button");
      btn.className = "kill-btn";
      btn.type = "button";
      btn.textContent = safeNameAvailable ? "종료" : "강행 종료";
      btn.addEventListener("click", async () => {
        const expectedProcessName = safeNameAvailable ? row.process_name.trim() : null;
        const warningText = safeNameAvailable
          ? ""
          : "\n프로세스명을 확인하지 못해 강행 종료를 시도합니다.";
        const ok = window.confirm(
          `PID ${row.pid} (${row.process_name ?? "unknown"}) 프로세스를 종료할까요?${warningText}`,
        );
        if (!ok) {
          return;
        }

        const kill = await invoke("kill_process_by_pid", {
          pid: row.pid,
          expectedProcessName,
          allowMismatch: allowMismatch || !safeNameAvailable,
        });
        if (!kill.ok) {
          window.alert(`종료 실패 [${kill.code}]: ${kill.message}`);
        } else if (kill.code === "KILLED_WITH_WARNING") {
          window.alert(`주의: ${kill.message}`);
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
killAllowMismatchEl?.addEventListener("change", renderCurrentRows);

(async function init() {
  await loadDefaultProfile();
  applyMonitorState();
  await runScanOnce();
})();

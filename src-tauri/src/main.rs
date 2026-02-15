#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use port_watch::portscan::{kill_pid, parse_ports_expr, scan_ports, PortStatus, DEFAULT_PORTS_EXPR, DEFAULT_PROFILE_NAME};
use serde::Serialize;

#[derive(Serialize)]
struct DefaultProfile {
    name: String,
    ports_expr: String,
}

#[derive(Serialize)]
struct KillResult {
    ok: bool,
    message: String,
}

#[tauri::command]
fn scan_ports_cmd(host: String, ports_expr: String, timeout_ms: u64) -> Result<Vec<PortStatus>, String> {
    if host.trim().is_empty() {
        return Err("host is empty".to_string());
    }

    let ports = parse_ports_expr(&ports_expr);
    if ports.is_empty() {
        return Ok(vec![]);
    }

    Ok(scan_ports(&host, &ports, timeout_ms))
}

#[tauri::command]
fn kill_process_by_pid(pid: u32) -> KillResult {
    match kill_pid(pid) {
        Ok(message) => KillResult { ok: true, message },
        Err(message) => KillResult { ok: false, message },
    }
}

#[tauri::command]
fn get_default_profile() -> DefaultProfile {
    DefaultProfile {
        name: DEFAULT_PROFILE_NAME.to_string(),
        ports_expr: DEFAULT_PORTS_EXPR.to_string(),
    }
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            scan_ports_cmd,
            kill_process_by_pid,
            get_default_profile
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

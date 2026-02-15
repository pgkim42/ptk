#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use port_watch::portscan::{
    kill_pid_checked, parse_ports_expr_strict, scan_ports, KillError, KillMode, KillRequest,
    KillResultKind, PortStatus, DEFAULT_PORTS_EXPR, DEFAULT_PROFILE_NAME,
};
use serde::Serialize;

#[derive(Serialize)]
struct DefaultProfile {
    name: String,
    ports_expr: String,
}

#[derive(Serialize)]
struct KillResult {
    ok: bool,
    code: String,
    message: String,
}

#[tauri::command]
fn scan_ports_cmd(
    host: String,
    ports_expr: String,
    timeout_ms: u64,
) -> Result<Vec<PortStatus>, String> {
    if host.trim().is_empty() {
        return Err("host is empty".to_string());
    }

    let ports = parse_ports_expr_strict(&ports_expr)?;
    if ports.is_empty() {
        return Ok(vec![]);
    }

    Ok(scan_ports(&host, &ports, timeout_ms))
}

fn kill_success_message(pid: u32, mode: KillMode, result: &KillResultKind) -> String {
    let prefix = if mode == KillMode::Force {
        "강제 종료 완료"
    } else {
        "종료 완료"
    };

    match result {
        KillResultKind::Killed => format!("{}: pid {}", prefix, pid),
        KillResultKind::KilledWithWarning(warning) => {
            format!("{}: pid {} (주의: {})", prefix, pid, warning)
        }
    }
}

fn map_kill_error(error: KillError) -> KillResult {
    KillResult {
        ok: false,
        code: error.code().to_string(),
        message: error.message(),
    }
}

#[tauri::command]
fn kill_process_by_pid(
    pid: u32,
    expected_process_name: Option<String>,
    allow_mismatch: bool,
) -> KillResult {
    match kill_pid_checked(KillRequest {
        pid,
        mode: KillMode::Soft,
        expected_process_name,
        allow_mismatch,
    }) {
        Ok(result) => {
            let code = match &result {
                KillResultKind::Killed => "KILLED",
                KillResultKind::KilledWithWarning(_) => "KILLED_WITH_WARNING",
            };

            KillResult {
                ok: true,
                code: code.to_string(),
                message: kill_success_message(pid, KillMode::Soft, &result),
            }
        }
        Err(error) => map_kill_error(error),
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

#[cfg(test)]
mod tests {
    use super::{kill_success_message, map_kill_error, scan_ports_cmd};
    use port_watch::portscan::{KillError, KillMode, KillResultKind};

    #[test]
    fn scan_ports_cmd_returns_error_on_invalid_ports() {
        let result = scan_ports_cmd("127.0.0.1".to_string(), "8080, nope".to_string(), 300);
        let err = result.unwrap_err();
        assert!(err.contains("invalid ports:"));
    }

    #[test]
    fn kill_success_message_includes_warning_when_present() {
        let msg = kill_success_message(
            1234,
            KillMode::Soft,
            &KillResultKind::KilledWithWarning("mismatch".to_string()),
        );
        assert!(msg.contains("pid 1234"));
        assert!(msg.contains("mismatch"));
    }

    #[test]
    fn map_kill_error_uses_expected_code() {
        let result = map_kill_error(KillError::GuardMismatch {
            expected: "node".to_string(),
            actual: Some("java".to_string()),
        });
        assert!(!result.ok);
        assert_eq!(result.code, "BLOCKED_MISMATCH");
    }
}

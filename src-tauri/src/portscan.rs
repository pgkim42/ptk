use serde::Serialize;
use std::collections::{BTreeSet, HashMap};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::process::Command;
use std::time::Duration;

pub const MAX_PORT_COUNT: usize = 5000;

#[derive(Debug, Clone, Serialize)]
pub struct PortStatus {
    pub port: u16,
    pub open: bool,
    pub pid: Option<u32>,
    pub process_name: Option<String>,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KillMode {
    Soft,
    Force,
}

#[derive(Debug, Clone)]
pub struct KillRequest {
    pub pid: u32,
    pub mode: KillMode,
    pub expected_process_name: Option<String>,
    pub allow_mismatch: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KillResultKind {
    Killed,
    KilledWithWarning(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KillError {
    InvalidPid,
    LookupFailed {
        pid: u32,
    },
    GuardMismatch {
        expected: String,
        actual: Option<String>,
    },
    CommandFailed(String),
}

impl KillError {
    pub fn code(&self) -> &'static str {
        match self {
            KillError::InvalidPid => "INVALID_PID",
            KillError::LookupFailed { .. } => "BLOCKED_LOOKUP",
            KillError::GuardMismatch { .. } => "BLOCKED_MISMATCH",
            KillError::CommandFailed(_) => "COMMAND_FAILED",
        }
    }

    pub fn message(&self) -> String {
        match self {
            KillError::InvalidPid => "잘못된 PID입니다.".to_string(),
            KillError::LookupFailed { pid } => {
                format!(
                    "PID {} 프로세스 정보를 조회하지 못해 종료를 차단했습니다.",
                    pid
                )
            }
            KillError::GuardMismatch { expected, actual } => match actual {
                Some(actual) => format!(
                    "프로세스 정보 불일치로 종료를 차단했습니다. expected='{}', actual='{}'",
                    expected, actual
                ),
                None => format!(
                    "프로세스 정보 불일치로 종료를 차단했습니다. expected='{}'",
                    expected
                ),
            },
            KillError::CommandFailed(detail) => detail.clone(),
        }
    }
}

pub const DEFAULT_PROFILE_NAME: &str = "framework-default";
pub const DEFAULT_PORTS_EXPR: &str = "3000-3009,5173-5182,4200-4209,8080-8089";

pub fn parse_ports_expr_strict(input: &str) -> Result<Vec<u16>, String> {
    let mut out = BTreeSet::new();
    let mut invalid_tokens = Vec::new();

    for token in input
        .split(|c: char| c == ',' || c.is_ascii_whitespace())
        .map(str::trim)
        .filter(|v| !v.is_empty())
    {
        if let Some((s, e)) = token.split_once('-') {
            let start = s.trim().parse::<u16>();
            let end = e.trim().parse::<u16>();
            match (start, end) {
                (Ok(start), Ok(end)) if start > 0 && start <= end => {
                    for p in start..=end {
                        out.insert(p);
                        if out.len() > MAX_PORT_COUNT {
                            return Err(format!(
                                "too many ports: {} (max {})",
                                out.len(),
                                MAX_PORT_COUNT
                            ));
                        }
                    }
                }
                _ => invalid_tokens.push(token.to_string()),
            }
            continue;
        }

        match token.parse::<u16>() {
            Ok(port) if port > 0 => {
                out.insert(port);
                if out.len() > MAX_PORT_COUNT {
                    return Err(format!(
                        "too many ports: {} (max {})",
                        out.len(),
                        MAX_PORT_COUNT
                    ));
                }
            }
            _ => invalid_tokens.push(token.to_string()),
        }
    }

    if !invalid_tokens.is_empty() {
        return Err(format!("invalid ports: {}", invalid_tokens.join(", ")));
    }

    Ok(out.into_iter().collect())
}

pub fn scan_ports(host: &str, ports: &[u16], timeout_ms: u64) -> Vec<PortStatus> {
    let timeout = Duration::from_millis(timeout_ms.max(50));

    let pid_map = if is_local_host(host) {
        port_pid_map().unwrap_or_default()
    } else {
        HashMap::new()
    };

    let mut out = Vec::with_capacity(ports.len());

    for &port in ports {
        let addr_text = format!("{}:{}", host, port);
        let target = resolve_first(&addr_text);

        match target {
            Some(addr) => match TcpStream::connect_timeout(&addr, timeout) {
                Ok(_) => {
                    let pid = pid_map.get(&port).copied();
                    out.push(PortStatus {
                        port,
                        open: true,
                        pid,
                        process_name: pid.and_then(process_name_by_pid),
                        message: "connection succeeded".to_string(),
                    });
                }
                Err(err) => {
                    out.push(PortStatus {
                        port,
                        open: false,
                        pid: None,
                        process_name: None,
                        message: err.to_string(),
                    });
                }
            },
            None => out.push(PortStatus {
                port,
                open: false,
                pid: None,
                process_name: None,
                message: format!("invalid address: {}", addr_text),
            }),
        }
    }

    out
}

pub fn kill_pid_checked(request: KillRequest) -> Result<KillResultKind, KillError> {
    let KillRequest {
        pid,
        mode,
        expected_process_name,
        allow_mismatch,
    } = request;

    if pid == 0 {
        return Err(KillError::InvalidPid);
    }

    let expected = expected_process_name.and_then(|v| normalize_non_empty_name(&v));
    let warning = if let Some(expected_name) = expected {
        let actual = process_name_by_pid(pid);
        evaluate_kill_guard(pid, &expected_name, actual, allow_mismatch)?
    } else {
        None
    };

    execute_kill(pid, mode).map_err(KillError::CommandFailed)?;

    if let Some(warning) = warning {
        Ok(KillResultKind::KilledWithWarning(warning))
    } else {
        Ok(KillResultKind::Killed)
    }
}

pub fn kill_pid(pid: u32, mode: KillMode) -> Result<String, String> {
    match kill_pid_checked(KillRequest {
        pid,
        mode,
        expected_process_name: None,
        allow_mismatch: false,
    }) {
        Ok(_) => Ok(format!("{} pid {}", success_label(mode), pid)),
        Err(err) => Err(err.message()),
    }
}

fn evaluate_kill_guard(
    pid: u32,
    expected: &str,
    actual: Option<String>,
    allow_mismatch: bool,
) -> Result<Option<String>, KillError> {
    match actual {
        Some(actual_name) if names_match(expected, &actual_name) => Ok(None),
        Some(actual_name) => {
            if allow_mismatch {
                Ok(Some(format!(
                    "프로세스명 불일치 상태로 강행합니다. expected='{}', actual='{}'",
                    expected, actual_name
                )))
            } else {
                Err(KillError::GuardMismatch {
                    expected: expected.to_string(),
                    actual: Some(actual_name),
                })
            }
        }
        None => {
            if allow_mismatch {
                Ok(Some(format!(
                    "PID {} 프로세스명 조회 실패 상태로 강행합니다.",
                    pid
                )))
            } else {
                Err(KillError::LookupFailed { pid })
            }
        }
    }
}

fn execute_kill(pid: u32, mode: KillMode) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let pid_text = pid.to_string();
        let mut args = vec!["/PID", pid_text.as_str()];
        if mode == KillMode::Force {
            args.push("/F");
        }

        let output = Command::new("taskkill")
            .args(args)
            .output()
            .map_err(|e| format!("failed to execute taskkill: {}", e))?;

        if output.status.success() {
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("taskkill failed: {}", stderr.trim()));
    }

    #[cfg(not(target_os = "windows"))]
    {
        let signal = if mode == KillMode::Force {
            "-KILL"
        } else {
            "-TERM"
        };
        let output = Command::new("kill")
            .args([signal, &pid.to_string()])
            .output()
            .map_err(|e| format!("failed to execute kill: {}", e))?;

        if output.status.success() {
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("kill failed: {}", stderr.trim()))
    }
}

fn success_label(mode: KillMode) -> &'static str {
    if mode == KillMode::Force {
        "force-killed"
    } else {
        "killed"
    }
}

fn normalize_non_empty_name(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn names_match(expected: &str, actual: &str) -> bool {
    expected.trim().eq_ignore_ascii_case(actual.trim())
}

fn resolve_first(addr: &str) -> Option<SocketAddr> {
    addr.to_socket_addrs().ok()?.next()
}

fn is_local_host(host: &str) -> bool {
    let h = host.trim().to_ascii_lowercase();
    h == "127.0.0.1" || h == "localhost" || h == "::1"
}

#[cfg(target_os = "windows")]
fn port_pid_map() -> Result<HashMap<u16, u32>, String> {
    let output = Command::new("netstat")
        .args(["-ano", "-p", "tcp"])
        .output()
        .map_err(|e| format!("failed to execute netstat: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("netstat failed: {}", stderr.trim()));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(parse_windows_netstat_listening_pid_map(&stdout))
}

#[cfg(not(target_os = "windows"))]
fn port_pid_map() -> Result<HashMap<u16, u32>, String> {
    let output = Command::new("ss")
        .args(["-ltnp"])
        .output()
        .map_err(|e| format!("failed to execute ss: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("ss failed: {}", stderr.trim()));
    }

    let mut out = HashMap::new();
    let stdout = String::from_utf8_lossy(&output.stdout);

    for line in stdout.lines().skip(1) {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 6 {
            continue;
        }

        let local = cols[3];
        let proc_col = cols[5..].join(" ");
        let port = parse_port_from_addr(local);
        let pid = parse_pid_from_ss_process(&proc_col);
        if let (Some(port), Some(pid)) = (port, pid) {
            if pid > 0 {
                out.entry(port).or_insert(pid);
            }
        }
    }

    Ok(out)
}

#[cfg(any(target_os = "windows", test))]
fn parse_windows_netstat_listening_pid_map(stdout: &str) -> HashMap<u16, u32> {
    let mut out = HashMap::new();

    for line in stdout.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        // Proto Local Address Foreign Address State PID
        if cols.len() < 5 {
            continue;
        }

        let state = cols[3];
        if !state.eq_ignore_ascii_case("LISTENING") {
            continue;
        }

        let local = cols[1];
        let pid = cols[4].parse::<u32>().ok();
        let port = parse_port_from_addr(local);
        if let (Some(port), Some(pid)) = (port, pid) {
            if pid > 0 {
                out.entry(port).or_insert(pid);
            }
        }
    }

    out
}

fn parse_port_from_addr(addr: &str) -> Option<u16> {
    if addr.is_empty() {
        return None;
    }

    // IPv6 example: [::]:8080
    if let Some(end) = addr.rfind(']') {
        let rest = addr.get(end + 1..)?;
        if let Some(port) = rest.strip_prefix(':') {
            return port.parse::<u16>().ok();
        }
    }

    // IPv4 / wildcard example: 0.0.0.0:8080, *:8080
    addr.rsplit_once(':')?.1.parse::<u16>().ok()
}

fn parse_pid_from_ss_process(proc_col: &str) -> Option<u32> {
    let marker = "pid=";
    let start = proc_col.find(marker)? + marker.len();
    let tail = proc_col.get(start..)?;
    let pid_text: String = tail.chars().take_while(|c| c.is_ascii_digit()).collect();
    pid_text.parse::<u32>().ok()
}

#[cfg(target_os = "windows")]
fn process_name_by_pid(pid: u32) -> Option<String> {
    let output = Command::new("tasklist")
        .args(["/FI", &format!("PID eq {}", pid), "/FO", "CSV", "/NH"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let line = stdout.lines().next()?.trim();
    if line.is_empty() || line.contains("No tasks") {
        return None;
    }

    // CSV first field is image name.
    let first = line.split(',').next()?.trim().trim_matches('"');
    if first.is_empty() {
        None
    } else {
        Some(first.to_string())
    }
}

#[cfg(not(target_os = "windows"))]
fn process_name_by_pid(pid: u32) -> Option<String> {
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "comm="])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let name = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if name.is_empty() {
        None
    } else {
        Some(name)
    }
}

#[cfg(test)]
mod tests {
    use super::{
        evaluate_kill_guard, names_match, parse_pid_from_ss_process, parse_port_from_addr,
        parse_ports_expr_strict, parse_windows_netstat_listening_pid_map, KillError,
        MAX_PORT_COUNT,
    };

    #[test]
    fn parse_ports_expr_handles_list_and_range() {
        let got = parse_ports_expr_strict("8080, 3000-3002, 8080").unwrap();
        assert_eq!(got, vec![3000, 3001, 3002, 8080]);
    }

    #[test]
    fn parse_ports_expr_returns_invalid_tokens() {
        let err = parse_ports_expr_strict("8080, nope, 3000-2x").unwrap_err();
        assert!(err.contains("invalid ports:"));
        assert!(err.contains("nope"));
        assert!(err.contains("3000-2x"));
    }

    #[test]
    fn parse_ports_expr_enforces_max_port_count() {
        let expr = format!("1-{}", MAX_PORT_COUNT + 1);
        let err = parse_ports_expr_strict(&expr).unwrap_err();
        assert!(err.contains("too many ports"));
    }

    #[test]
    fn parse_windows_netstat_uses_listening_only_and_first_pid() {
        let sample = "\
  Proto  Local Address          Foreign Address        State           PID\n\
  TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING       111\n\
  TCP    127.0.0.1:3000         127.0.0.1:54000        ESTABLISHED     222\n\
  TCP    [::]:8080              [::]:0                 LISTENING       333\n\
  TCP    0.0.0.0:8080           0.0.0.0:0              LISTENING       444\n";

        let map = parse_windows_netstat_listening_pid_map(sample);
        assert_eq!(map.get(&3000), Some(&111));
        assert_eq!(map.get(&8080), Some(&333));
    }

    #[test]
    fn parse_port_from_addr_works() {
        assert_eq!(parse_port_from_addr("0.0.0.0:8080"), Some(8080));
        assert_eq!(parse_port_from_addr("*:5173"), Some(5173));
        assert_eq!(parse_port_from_addr("[::]:4200"), Some(4200));
        assert_eq!(parse_port_from_addr("invalid"), None);
    }

    #[test]
    fn parse_pid_from_ss_process_works() {
        let input = r#"users:((\"node\",pid=12345,fd=23))"#;
        assert_eq!(parse_pid_from_ss_process(input), Some(12345));
    }

    #[test]
    fn names_match_is_trimmed_and_case_insensitive() {
        assert!(names_match(" Node ", "node"));
        assert!(names_match("Vite", "vite"));
        assert!(!names_match("node", "java"));
    }

    #[test]
    fn evaluate_kill_guard_blocks_mismatch_without_override() {
        let result = evaluate_kill_guard(123, "node", Some("java".to_string()), false);
        assert_eq!(
            result.unwrap_err(),
            KillError::GuardMismatch {
                expected: "node".to_string(),
                actual: Some("java".to_string()),
            }
        );
    }

    #[test]
    fn evaluate_kill_guard_returns_warning_when_mismatch_override_enabled() {
        let warning = evaluate_kill_guard(123, "node", Some("java".to_string()), true)
            .unwrap()
            .unwrap();
        assert!(warning.contains("강행"));
        assert!(warning.contains("expected='node'"));
    }

    #[test]
    fn evaluate_kill_guard_blocks_lookup_failure_without_override() {
        let result = evaluate_kill_guard(9876, "node", None, false);
        assert_eq!(result.unwrap_err(), KillError::LookupFailed { pid: 9876 });
    }

    #[test]
    fn evaluate_kill_guard_allows_lookup_failure_with_override() {
        let warning = evaluate_kill_guard(9876, "node", None, true)
            .unwrap()
            .unwrap();
        assert!(warning.contains("조회 실패"));
        assert!(warning.contains("9876"));
    }
}

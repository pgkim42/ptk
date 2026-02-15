use serde::Serialize;
use std::collections::{BTreeSet, HashMap};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::process::Command;
use std::time::Duration;

#[derive(Debug, Clone, Serialize)]
pub struct PortStatus {
    pub port: u16,
    pub open: bool,
    pub pid: Option<u32>,
    pub process_name: Option<String>,
    pub message: String,
}

pub const DEFAULT_PROFILE_NAME: &str = "framework-default";
pub const DEFAULT_PORTS_EXPR: &str = "3000-3009,5173-5182,4200-4209,8080-8089";

pub fn parse_ports_expr(input: &str) -> Vec<u16> {
    let mut out = BTreeSet::new();

    for token in input
        .split(|c: char| c == ',' || c.is_ascii_whitespace())
        .map(str::trim)
        .filter(|v| !v.is_empty())
    {
        if let Some((s, e)) = token.split_once('-') {
            let start = s.trim().parse::<u16>();
            let end = e.trim().parse::<u16>();
            if let (Ok(start), Ok(end)) = (start, end) {
                if start > 0 && start <= end {
                    for p in start..=end {
                        out.insert(p);
                    }
                }
            }
            continue;
        }

        if let Ok(port) = token.parse::<u16>() {
            if port > 0 {
                out.insert(port);
            }
        }
    }

    out.into_iter().collect()
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

pub fn kill_pid(pid: u32) -> Result<String, String> {
    if pid == 0 {
        return Err("invalid pid".to_string());
    }

    #[cfg(target_os = "windows")]
    {
        let output = Command::new("taskkill")
            .args(["/PID", &pid.to_string(), "/F"])
            .output()
            .map_err(|e| format!("failed to execute taskkill: {}", e))?;

        if output.status.success() {
            return Ok(format!("killed pid {}", pid));
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("taskkill failed: {}", stderr.trim()));
    }

    #[cfg(not(target_os = "windows"))]
    {
        let output = Command::new("kill")
            .args(["-9", &pid.to_string()])
            .output()
            .map_err(|e| format!("failed to execute kill: {}", e))?;

        if output.status.success() {
            return Ok(format!("killed pid {}", pid));
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("kill failed: {}", stderr.trim()))
    }
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

    let mut out = HashMap::new();
    let stdout = String::from_utf8_lossy(&output.stdout);

    for line in stdout.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 5 {
            continue;
        }
        let local = cols[1];
        let pid = cols[4].parse::<u32>().ok();
        let port = parse_port_from_addr(local);
        if let (Some(port), Some(pid)) = (port, pid) {
            if pid > 0 {
                out.insert(port, pid);
            }
        }
    }

    Ok(out)
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
                out.insert(port, pid);
            }
        }
    }

    Ok(out)
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
    use super::{parse_pid_from_ss_process, parse_port_from_addr, parse_ports_expr};

    #[test]
    fn parse_ports_expr_handles_list_and_range() {
        let got = parse_ports_expr("8080, 3000-3002, 8080, nope, 0");
        assert_eq!(got, vec![3000, 3001, 3002, 8080]);
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
}

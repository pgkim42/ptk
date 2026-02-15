use clap::{Parser, Subcommand};
use comfy_table::{
    modifiers::UTF8_ROUND_CORNERS, presets::UTF8_FULL, Attribute, Cell, Color, ContentArrangement,
    Table,
};
use port_watch::portscan::{kill_pid, parse_ports_expr, scan_ports, DEFAULT_PORTS_EXPR};
use std::thread;
use std::time::Duration;

#[derive(Parser)]
#[command(name = "port-watch-cli")]
#[command(about = "Dev port monitor for leftover local servers")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Scan {
        #[arg(long, default_value = "127.0.0.1")]
        host: String,
        #[arg(long)]
        ports: Option<String>,
        #[arg(long, default_value_t = 300)]
        timeout: u64,
        #[arg(long)]
        json: bool,
        #[arg(long, default_value_t = false)]
        open_only: bool,
        #[arg(long, default_value_t = false)]
        use_default: bool,
    },
    Watch {
        #[arg(long, default_value = "127.0.0.1")]
        host: String,
        #[arg(long)]
        ports: Option<String>,
        #[arg(long, default_value_t = 300)]
        timeout: u64,
        #[arg(long, default_value_t = 3)]
        interval: u64,
        #[arg(long)]
        json: bool,
        #[arg(long, default_value_t = false)]
        open_only: bool,
        #[arg(long, default_value_t = true)]
        use_default: bool,
    },
    Kill {
        #[arg(long)]
        pid: u32,
        #[arg(long, default_value_t = false)]
        yes: bool,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Scan {
            host,
            ports,
            timeout,
            json,
            open_only,
            use_default,
        } => {
            let expr = resolve_ports_expr(ports, use_default);
            run_scan_once(&host, &expr, timeout, json, open_only);
        }
        Commands::Watch {
            host,
            ports,
            timeout,
            interval,
            json,
            open_only,
            use_default,
        } => {
            let expr = resolve_ports_expr(ports, use_default);
            loop {
                run_scan_once(&host, &expr, timeout, json, open_only);
                thread::sleep(Duration::from_secs(interval.max(1)));
            }
        }
        Commands::Kill { pid, yes } => {
            if !yes {
                eprintln!("refusing to kill without --yes (pid={})", pid);
                std::process::exit(2);
            }
            match kill_pid(pid) {
                Ok(msg) => println!("{}", msg),
                Err(err) => {
                    eprintln!("{}", err);
                    std::process::exit(1);
                }
            }
        }
    }
}

fn resolve_ports_expr(ports: Option<String>, use_default: bool) -> String {
    match (ports, use_default) {
        (Some(v), _) => v,
        (None, true) => DEFAULT_PORTS_EXPR.to_string(),
        (None, false) => {
            eprintln!("ports are required unless --use-default is enabled");
            std::process::exit(2);
        }
    }
}

fn run_scan_once(host: &str, ports_expr: &str, timeout: u64, json: bool, open_only: bool) {
    let ports = parse_ports_expr(ports_expr);
    let mut rows = scan_ports(host, &ports, timeout);
    if open_only {
        rows.retain(|row| row.open);
    }

    if json {
        match serde_json::to_string_pretty(&rows) {
            Ok(s) => println!("{}", s),
            Err(err) => {
                eprintln!("failed to serialize json: {}", err);
                std::process::exit(1);
            }
        }
        return;
    }

    let open_count = rows.iter().filter(|r| r.open).count();
    let closed_count = rows.len().saturating_sub(open_count);

    let mut table = Table::new();
    table
        .load_preset(UTF8_FULL)
        .apply_modifier(UTF8_ROUND_CORNERS)
        .set_content_arrangement(ContentArrangement::Dynamic)
        .set_header(vec![
            Cell::new("PORT").add_attribute(Attribute::Bold),
            Cell::new("STATE").add_attribute(Attribute::Bold),
            Cell::new("PID").add_attribute(Attribute::Bold),
            Cell::new("PROCESS").add_attribute(Attribute::Bold),
            Cell::new("DETAIL").add_attribute(Attribute::Bold),
        ]);

    for row in rows {
        let state = if row.open {
            Cell::new("OPEN").fg(Color::Green).add_attribute(Attribute::Bold)
        } else {
            Cell::new("CLOSED").fg(Color::Red)
        };

        table.add_row(vec![
            Cell::new(row.port),
            state,
            Cell::new(row.pid.map(|v| v.to_string()).unwrap_or_else(|| "-".to_string())),
            Cell::new(row.process_name.unwrap_or_else(|| "-".to_string())),
            Cell::new(short_detail(&localize_detail(&row.message))),
        ]);
    }

    println!("host={host} | timeout={}ms", timeout);
    println!("ports={ports_expr}");
    println!("summary: OPEN={open_count}, CLOSED={closed_count}");
    println!("{table}\n");
}

fn short_detail(message: &str) -> String {
    const MAX: usize = 48;
    if message.len() <= MAX {
        return message.to_string();
    }
    let mut s = message.chars().take(MAX - 3).collect::<String>();
    s.push_str("...");
    s
}

fn localize_detail(message: &str) -> String {
    let lower = message.to_ascii_lowercase();

    if lower.contains("connection succeeded") {
        return "연결 성공".to_string();
    }
    if lower.contains("connection refused") {
        return "연결 거부됨".to_string();
    }
    if lower.contains("timed out") {
        return "연결 시간 초과".to_string();
    }
    if lower.contains("invalid address") {
        return "잘못된 주소 형식".to_string();
    }
    if lower.contains("no route to host") {
        return "호스트 경로 없음".to_string();
    }
    if lower.contains("network is unreachable") {
        return "네트워크에 도달할 수 없음".to_string();
    }
    if lower.contains("permission denied") {
        return "권한 거부됨".to_string();
    }

    message.to_string()
}

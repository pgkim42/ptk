use clap::{Parser, Subcommand};
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
            use_default,
        } => {
            let expr = resolve_ports_expr(ports, use_default);
            run_scan_once(&host, &expr, timeout, json);
        }
        Commands::Watch {
            host,
            ports,
            timeout,
            interval,
            json,
            use_default,
        } => {
            let expr = resolve_ports_expr(ports, use_default);
            loop {
                run_scan_once(&host, &expr, timeout, json);
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

fn run_scan_once(host: &str, ports_expr: &str, timeout: u64, json: bool) {
    let ports = parse_ports_expr(ports_expr);
    let rows = scan_ports(host, &ports, timeout);

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

    println!("host={} ports={} timeout={}ms", host, ports_expr, timeout);
    println!("{:<8} {:<8} {:<8} {:<24} {}", "PORT", "STATE", "PID", "PROCESS", "DETAIL");
    for row in rows {
        println!(
            "{:<8} {:<8} {:<8} {:<24} {}",
            row.port,
            if row.open { "OPEN" } else { "CLOSED" },
            row.pid
                .map(|v| v.to_string())
                .unwrap_or_else(|| "-".to_string()),
            row.process_name.unwrap_or_else(|| "-".to_string()),
            row.message
        );
    }
    println!();
}

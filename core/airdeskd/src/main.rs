use std::env;
use std::path::PathBuf;
use std::process;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use airdeskd::{
    serve_unix, Clock, Daemon, DaemonConfig, LeaseRegistry, PtyConfig, UnixPtySpawner,
    DEFAULT_MAX_REPLAY_BYTES,
};

struct Options {
    socket: PathBuf,
    shell: String,
    shell_args: Vec<String>,
    columns: u16,
    rows: u16,
    lease_file: Option<PathBuf>,
    max_replay_bytes: usize,
    max_clients: usize,
}

fn main() {
    let options = match parse_args() {
        Ok(options) => options,
        Err(message) => {
            eprintln!("{message}");
            process::exit(2);
        }
    };

    let leases = match &options.lease_file {
        Some(path) => match std::fs::read_to_string(path) {
            Ok(text) => match LeaseRegistry::from_records(&text) {
                Ok(leases) => leases,
                Err(error) => {
                    eprintln!("{error}");
                    process::exit(2);
                }
            },
            Err(error) => {
                eprintln!("cannot read lease file {}: {error}", path.display());
                process::exit(2);
            }
        },
        None => LeaseRegistry::new(),
    };

    let pty = PtyConfig::shell(
        options.shell,
        options.shell_args,
        options.columns,
        options.rows,
    );
    let mut config = DaemonConfig::new(pty);
    config.max_replay_bytes = options.max_replay_bytes;
    config.max_clients = options.max_clients;
    let now: Clock = Arc::new(epoch_millis);
    let daemon = Arc::new(Daemon::new(config, Arc::new(UnixPtySpawner), leases, now));

    eprintln!("airdeskd listening on {}", options.socket.display());
    if let Err(error) = serve_unix(&options.socket, daemon) {
        eprintln!("airdeskd failed: {error}");
        process::exit(1);
    }
}

fn parse_args() -> Result<Options, String> {
    let mut socket = None;
    let mut shell = env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
    let mut shell_args = Vec::new();
    let mut columns = 80;
    let mut rows = 24;
    let mut lease_file = None;
    let mut max_replay_bytes = DEFAULT_MAX_REPLAY_BYTES;
    let mut max_clients = 8;
    let mut arguments = env::args().skip(1);
    while let Some(argument) = arguments.next() {
        if argument == "--" {
            shell_args.extend(arguments);
            break;
        }
        let mut value = || {
            arguments
                .next()
                .ok_or_else(|| format!("missing value for {argument}"))
        };
        match argument.as_str() {
            "--socket" => socket = Some(PathBuf::from(value()?)),
            "--shell" => shell = value()?,
            "--cols" => columns = parse(value()?, "columns")?,
            "--rows" => rows = parse(value()?, "rows")?,
            "--lease-file" => lease_file = Some(PathBuf::from(value()?)),
            "--max-replay-bytes" => max_replay_bytes = parse(value()?, "max replay bytes")?,
            "--max-clients" => max_clients = parse(value()?, "max clients")?,
            "--help" | "-h" => {
                println!(
                    "airdeskd --socket PATH [--shell PATH] [--cols N] [--rows N]\n\
                     \x20        [--lease-file PATH] [--max-replay-bytes N] [--max-clients N] [-- ARGS...]"
                );
                process::exit(0);
            }
            _ => return Err(format!("unknown argument {argument}")),
        }
    }
    let socket = socket.ok_or_else(|| "--socket PATH is required".to_string())?;
    if shell.is_empty() {
        return Err("invalid shell path".to_string());
    }
    Ok(Options {
        socket,
        shell,
        shell_args,
        columns,
        rows,
        lease_file,
        max_replay_bytes,
        max_clients,
    })
}

fn parse<T: std::str::FromStr>(value: String, name: &str) -> Result<T, String> {
    value.parse().map_err(|_| format!("invalid {name}"))
}

fn epoch_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

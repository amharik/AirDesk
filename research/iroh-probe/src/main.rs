use std::{
    env,
    error::Error,
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};

use iroh::{
    Endpoint, EndpointAddr, EndpointId, RelayMode, RelayUrl, TransportAddr,
    endpoint::{Connection, presets},
    protocol::{AcceptError, ProtocolHandler, Router},
};
use serde_json::{Value, json};

const ALPN: &[u8] = b"airdesk/iroh-probe/0";
const MAX_PAYLOAD_BYTES: usize = 1_048_576;
const TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Loopback,
    Server,
    Client,
}

impl Mode {
    fn parse(value: &str) -> Result<Self, Box<dyn Error>> {
        match value {
            "loopback" => Ok(Self::Loopback),
            "server" => Ok(Self::Server),
            "client" => Ok(Self::Client),
            _ => Err(format!("unknown mode: {value}").into()),
        }
    }
}

#[derive(Debug)]
struct Args {
    mode: Mode,
    samples: usize,
    payload_bytes: usize,
    bind_addr: String,
    peer_id: String,
    peer_addr: String,
    peer_relay: String,
    relay: bool,
    network: String,
    run_id: String,
    commit: String,
    dirty: bool,
    date: String,
    host_os: String,
    host_arch: String,
    cargo_version: String,
}

impl Default for Args {
    fn default() -> Self {
        Self {
            mode: Mode::Loopback,
            samples: 30,
            payload_bytes: 64,
            bind_addr: "127.0.0.1:0".to_string(),
            peer_id: String::new(),
            peer_addr: String::new(),
            peer_relay: String::new(),
            relay: false,
            network: "loopback".to_string(),
            run_id: "unknown".to_string(),
            commit: "unknown".to_string(),
            dirty: false,
            date: "unknown".to_string(),
            host_os: "unknown".to_string(),
            host_arch: "unknown".to_string(),
            cargo_version: "unknown".to_string(),
        }
    }
}

#[derive(Debug, Clone)]
struct Echo {
    received: Arc<AtomicUsize>,
}

impl ProtocolHandler for Echo {
    async fn accept(&self, connection: Connection) -> Result<(), AcceptError> {
        loop {
            let (mut send, mut recv) = match connection.accept_bi().await {
                Ok(stream) => stream,
                Err(_) => break,
            };
            let received = self.received.clone();
            tokio::spawn(async move {
                match tokio::io::copy(&mut recv, &mut send).await {
                    Ok(_) => {
                        received.fetch_add(1, Ordering::Relaxed);
                    }
                    Err(error) => {
                        eprintln!("echo copy failed: {error}");
                    }
                }
                if let Err(error) = send.finish() {
                    eprintln!("echo finish failed: {error}");
                }
            });
        }
        connection.closed().await;
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args = parse_args()?;
    match args.mode {
        Mode::Server => run_server(&args).await,
        Mode::Loopback => run_loopback(args).await,
        Mode::Client => run_client(args).await,
    }
}

async fn run_server(args: &Args) -> Result<(), Box<dyn Error>> {
    if args.bind_addr.is_empty() {
        return Err("server mode requires --bind-addr".into());
    }

    let received = Arc::new(AtomicUsize::new(0));
    let endpoint = bind_network_endpoint(&args.bind_addr, args.relay).await?;
    let addr = endpoint.addr();
    let relay_urls: Vec<String> = addr.relay_urls().map(ToString::to_string).collect();
    if args.relay && relay_urls.is_empty() {
        return Err("relay mode requested but no relay address was assigned".into());
    }
    if !args.relay && !relay_urls.is_empty() {
        return Err("relay address present despite RelayMode::Disabled".into());
    }
    let direct_addrs: Vec<String> = addr.ip_addrs().map(ToString::to_string).collect();
    if !args.relay && direct_addrs.is_empty() {
        return Err("server endpoint has no direct IP address".into());
    }

    let router = Router::builder(endpoint)
        .accept(
            ALPN,
            Echo {
                received: received.clone(),
            },
        )
        .spawn();

    let ready = json!({
        "event": "ready",
        "endpoint_id": addr.id.to_string(),
        "direct_addrs": direct_addrs,
        "relay_addrs": relay_urls.len(),
        "relay_url": relay_urls.first(),
        "relay_urls": relay_urls,
    });
    println!("{}", serde_json::to_string(&ready)?);
    use std::io::Write;
    std::io::stdout().flush()?;

    tokio::signal::ctrl_c().await?;
    router.shutdown().await?;
    Ok(())
}

async fn run_loopback(args: Args) -> Result<(), Box<dyn Error>> {
    validate_measurement_args(&args)?;

    let received = Arc::new(AtomicUsize::new(0));
    let server_endpoint = bind_loopback_endpoint().await?;
    let server_addr = server_endpoint.addr();
    if server_addr.relay_urls().next().is_some() {
        return Err("relay address present despite RelayMode::Disabled".into());
    }
    if server_addr.ip_addrs().next().is_none() {
        return Err("server endpoint has no direct IP address".into());
    }

    let router = Router::builder(server_endpoint)
        .accept(
            ALPN,
            Echo {
                received: received.clone(),
            },
        )
        .spawn();
    let client_endpoint = bind_loopback_endpoint().await?;

    let result = measure(&args, &client_endpoint, server_addr, Some(received), false).await?;

    client_endpoint.close().await;
    router.shutdown().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

async fn run_client(args: Args) -> Result<(), Box<dyn Error>> {
    validate_measurement_args(&args)?;
    if args.peer_id.is_empty() {
        return Err("client mode requires --peer-id".into());
    }
    if args.relay && args.peer_relay.is_empty() {
        return Err("relay client mode requires --peer-relay".into());
    }
    if !args.relay && args.peer_addr.is_empty() {
        return Err("client mode requires --peer-addr".into());
    }

    let peer_id: EndpointId = args.peer_id.parse()?;
    let peer_addr = if args.relay {
        let relay_url: RelayUrl = args.peer_relay.parse()?;
        EndpointAddr::from_parts(peer_id, [TransportAddr::Relay(relay_url)])
    } else {
        let peer_socket: SocketAddr = args.peer_addr.parse()?;
        EndpointAddr::from_parts(peer_id, [TransportAddr::Ip(peer_socket)])
    };

    let client_endpoint = bind_network_endpoint("0.0.0.0:0", args.relay).await?;
    if !args.relay && client_endpoint.addr().relay_urls().next().is_some() {
        return Err("relay address present despite RelayMode::Disabled".into());
    }

    let result = measure(&args, &client_endpoint, peer_addr, None, true).await?;
    client_endpoint.close().await;
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

async fn measure(
    args: &Args,
    client_endpoint: &Endpoint,
    peer_addr: EndpointAddr,
    server_messages: Option<Arc<AtomicUsize>>,
    redact_addrs: bool,
) -> Result<Value, Box<dyn Error>> {
    let payload = make_payload(args.payload_bytes);

    let connect_started = Instant::now();
    let connection = client_endpoint.connect(peer_addr.clone(), ALPN).await?;
    let connect_ms = elapsed_ms(connect_started);

    let mut rtts = Vec::with_capacity(args.samples);
    let mut failures = Vec::new();
    let mut delivered = 0usize;
    for sample in 0..args.samples {
        match echo_once(&connection, &payload).await {
            Ok(rtt_ms) => {
                rtts.push(rtt_ms);
                delivered += 1;
            }
            Err(error) => failures.push(format!("sample {sample}: {error}")),
        }
    }

    let paths = connection.paths();
    let path_count = paths.len();
    let direct_paths = paths.iter().filter(|path| path.is_ip()).count();
    let relay_paths = paths.iter().filter(|path| path.is_relay()).count();
    let selected_path = paths
        .iter()
        .find(|path| path.is_selected())
        .map(|path| {
            if path.is_ip() {
                "direct"
            } else if path.is_relay() {
                "relay"
            } else {
                "other"
            }
        })
        .unwrap_or("unknown");
    drop(paths);

    connection.close(0u32.into(), b"reconnect");
    let reconnect_started = Instant::now();
    let reconnect_connection = client_endpoint.connect(peer_addr.clone(), ALPN).await?;
    let reconnect_connect_ms = elapsed_ms(reconnect_started);
    let reconnect_echo_started = Instant::now();
    let reconnect_result = echo_once(&reconnect_connection, &payload).await;
    let reconnect_echo_ms = elapsed_ms(reconnect_echo_started);
    let reconnect_ms = elapsed_ms(reconnect_started);
    if let Err(error) = reconnect_result {
        failures.push(format!("reconnect echo: {error}"));
    }
    reconnect_connection.close(0u32.into(), b"done");

    let relay_addrs = peer_addr.relay_urls().count();
    let peer_addrs_count = peer_addr.addrs.len();
    let direct_addrs: Vec<String> = if redact_addrs {
        Vec::new()
    } else {
        peer_addr.ip_addrs().map(ToString::to_string).collect()
    };
    let expected_path = if args.relay { "relay" } else { "direct" };
    let relay_ok = if args.relay {
        relay_addrs > 0
    } else {
        relay_addrs == 0
    };
    let pass = failures.is_empty()
        && rtts.len() == args.samples
        && relay_ok
        && selected_path == expected_path;
    let server_messages = server_messages.map(|count| count.load(Ordering::Relaxed));
    let scenario_name = if args.relay {
        "iroh-quic-relay-fallback".to_string()
    } else {
        format!("iroh-quic-{}-baseline", args.network)
    };
    let observations = if args.network == "loopback" {
        format!(
            "Research measurement; not a product commitment. Relay-free loopback endpoint pair. Transport iroh. Server handled {} messages.",
            server_messages
                .map(|count| count.to_string())
                .unwrap_or_else(|| "n/a".to_string())
        )
    } else if args.relay {
        "Research measurement; not a product commitment. Iroh default relay path with IP transports disabled. This uses the public n0 relay map and is not an Adopt signal.".to_string()
    } else {
        format!(
            "Research measurement; not a product commitment. Relay-free direct IP endpoint pair over {}. No relay addresses configured. Transport iroh.",
            args.network
        )
    };

    Ok(json!({
        "schema_version": 1,
        "run_id": args.run_id,
        "scenario": "T4",
        "scenario_name": scenario_name,
        "evidence_scope": "transport-baseline",
        "candidate": "iroh-quic",
        "transport": "iroh",
        "commit": args.commit,
        "dirty": args.dirty,
        "build": "release",
        "date": args.date,
        "environment": {
            "controller": format!("cargo {}", args.cargo_version),
            "host": format!("macOS {} {}", args.host_os, args.host_arch),
            "browser": "n/a",
            "network": args.network
        },
        "samples": args.samples,
        "metrics": {
            "control_rtt_ms": {
                "p50": percentile(&rtts, 50),
                "p95": percentile(&rtts, 95),
                "p99": percentile(&rtts, 99),
                "min": rtts.iter().copied().reduce(f64::min).map(round_ms),
                "max": rtts.iter().copied().reduce(f64::max).map(round_ms)
            },
            "messages_delivered": delivered,
            "connect_ms": round_ms(connect_ms),
            "reconnect_ms": round_ms(reconnect_ms),
            "reconnect_connect_ms": round_ms(reconnect_connect_ms),
            "reconnect_echo_ms": round_ms(reconnect_echo_ms)
        },
        "diagnostics": {
            "server_messages_received": server_messages,
            "payload_bytes": args.payload_bytes,
            "timeout_ms": TIMEOUT.as_millis(),
            "relay_mode": if args.relay { "default" } else { "disabled" },
            "relay_addrs": relay_addrs,
            "direct_addrs": direct_addrs,
            "peer_addrs_count": peer_addrs_count,
            "peer_id": peer_addr.id.to_string(),
            "alpn": String::from_utf8_lossy(ALPN),
            "path_count": path_count,
            "direct_paths": direct_paths,
            "relay_paths": relay_paths,
            "selected_path": selected_path
        },
        "failures": failures,
        "observations": observations,
        "license_notes": "Iroh crate 1.4.1, MIT OR Apache-2.0; research-only pinned dependency outside the product graph.",
        "decision": if pass { "trial" } else { "hold" },
        "pass": pass
    }))
}

async fn bind_loopback_endpoint() -> Result<Endpoint, Box<dyn Error>> {
    let endpoint = Endpoint::builder(presets::Minimal)
        .relay_mode(RelayMode::Disabled)
        .clear_ip_transports()
        .bind_addr("127.0.0.1:0")?
        .bind()
        .await?;
    Ok(endpoint)
}

async fn bind_network_endpoint(bind_addr: &str, relay: bool) -> Result<Endpoint, Box<dyn Error>> {
    let builder = Endpoint::builder(presets::Minimal).relay_mode(RelayMode::Default);
    if relay {
        return Ok(builder.clear_ip_transports().bind().await?);
    }
    let endpoint = builder
        .relay_mode(RelayMode::Disabled)
        .bind_addr(bind_addr)?
        .bind()
        .await?;
    Ok(endpoint)
}

async fn echo_once(connection: &Connection, payload: &[u8]) -> Result<f64, Box<dyn Error>> {
    let started = Instant::now();
    let (mut send, mut recv) = connection.open_bi().await?;
    send.write_all(payload).await?;
    send.finish()?;
    let response =
        match tokio::time::timeout(TIMEOUT, recv.read_to_end(MAX_PAYLOAD_BYTES + 1)).await {
            Ok(result) => result?,
            Err(_) => return Err("echo timeout".into()),
        };
    if response != payload {
        return Err(format!(
            "echo mismatch: expected {} bytes, received {}",
            payload.len(),
            response.len()
        )
        .into());
    }
    Ok(elapsed_ms(started))
}

fn make_payload(size: usize) -> Vec<u8> {
    let mut payload = vec![0u8; size];
    payload[..4].copy_from_slice(b"ADFP");
    for (index, byte) in payload.iter_mut().enumerate().skip(4) {
        *byte = (index % 251) as u8;
    }
    payload
}

fn elapsed_ms(started: Instant) -> f64 {
    round_ms(started.elapsed().as_secs_f64() * 1000.0)
}

fn round_ms(value: f64) -> f64 {
    (value * 1000.0).round() / 1000.0
}

fn percentile(values: &[f64], rank: usize) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(f64::total_cmp);
    let index = ((rank as f64 / 100.0) * sorted.len() as f64).ceil() as usize;
    let index = index.saturating_sub(1).min(sorted.len() - 1);
    Some(round_ms(sorted[index]))
}

fn validate_measurement_args(args: &Args) -> Result<(), Box<dyn Error>> {
    if args.payload_bytes < 8 || args.payload_bytes > MAX_PAYLOAD_BYTES {
        return Err(format!("payload bytes must be between 8 and {MAX_PAYLOAD_BYTES}").into());
    }
    if args.samples == 0 || args.samples > 10_000 {
        return Err("samples must be between 1 and 10000".into());
    }
    Ok(())
}

fn parse_args() -> Result<Args, Box<dyn Error>> {
    let mut args = Args::default();
    let mut iter = env::args().skip(1);
    while let Some(flag) = iter.next() {
        let value = iter
            .next()
            .ok_or_else(|| format!("missing value for {flag}"))?;
        match flag.as_str() {
            "--mode" => args.mode = Mode::parse(&value)?,
            "--samples" => args.samples = value.parse()?,
            "--payload-bytes" => args.payload_bytes = value.parse()?,
            "--bind-addr" => args.bind_addr = value,
            "--peer-id" => args.peer_id = value,
            "--peer-addr" => args.peer_addr = value,
            "--peer-relay" => args.peer_relay = value,
            "--relay" => args.relay = value == "true",
            "--network" => args.network = value,
            "--run-id" => args.run_id = value,
            "--commit" => args.commit = value,
            "--dirty" => args.dirty = value == "true",
            "--date" => args.date = value,
            "--host-os" => args.host_os = value,
            "--host-arch" => args.host_arch = value,
            "--cargo-version" => args.cargo_version = value,
            _ => return Err(format!("unknown argument: {flag}").into()),
        }
    }
    Ok(args)
}

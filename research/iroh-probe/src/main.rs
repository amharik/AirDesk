use std::{
    env,
    error::Error,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};

use iroh::{
    Endpoint, RelayMode,
    endpoint::{Connection, presets},
    protocol::{AcceptError, ProtocolHandler, Router},
};
use serde_json::json;

const ALPN: &[u8] = b"airdesk/iroh-probe/0";
const MAX_PAYLOAD_BYTES: usize = 1_048_576;
const TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug)]
struct Args {
    samples: usize,
    payload_bytes: usize,
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
            samples: 30,
            payload_bytes: 64,
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
    if args.payload_bytes < 8 || args.payload_bytes > MAX_PAYLOAD_BYTES {
        return Err(format!("payload bytes must be between 8 and {MAX_PAYLOAD_BYTES}").into());
    }
    if args.samples == 0 || args.samples > 10_000 {
        return Err("samples must be between 1 and 10000".into());
    }

    let payload = make_payload(args.payload_bytes);
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

    let connect_started = Instant::now();
    let connection = client_endpoint.connect(server_addr.clone(), ALPN).await?;
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

    connection.close(0u32.into(), b"reconnect");
    let reconnect_started = Instant::now();
    let reconnect_connection = client_endpoint.connect(server_addr.clone(), ALPN).await?;
    let reconnect_connect_ms = elapsed_ms(reconnect_started);
    let reconnect_echo_started = Instant::now();
    let reconnect_result = echo_once(&reconnect_connection, &payload).await;
    let reconnect_echo_ms = elapsed_ms(reconnect_echo_started);
    let reconnect_ms = elapsed_ms(reconnect_started);
    if let Err(error) = reconnect_result {
        failures.push(format!("reconnect echo: {error}"));
    }
    reconnect_connection.close(0u32.into(), b"done");

    let server_messages = received.load(Ordering::Relaxed);
    let direct_addrs: Vec<String> = server_addr.ip_addrs().map(ToString::to_string).collect();
    let relay_addrs = server_addr.relay_urls().count();
    let pass = failures.is_empty() && rtts.len() == args.samples && relay_addrs == 0;

    let result = json!({
        "schema_version": 1,
        "run_id": args.run_id,
        "scenario": "T4",
        "scenario_name": "iroh-quic-loopback-baseline",
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
            "network": "loopback"
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
            "relay_mode": "disabled",
            "relay_addrs": relay_addrs,
            "direct_addrs": direct_addrs,
            "peer_id": server_addr.id.to_string(),
            "alpn": String::from_utf8_lossy(ALPN)
        },
        "failures": failures,
        "observations": format!(
            "Research measurement; not a product commitment. Relay-free loopback endpoint pair. Transport iroh. Server handled {server_messages} messages."
        ),
        "license_notes": "Iroh crate 1.4.1, MIT OR Apache-2.0; research-only pinned dependency outside the product graph.",
        "decision": if pass { "trial" } else { "hold" },
        "pass": pass
    });

    client_endpoint.close().await;
    router.shutdown().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
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

fn parse_args() -> Result<Args, Box<dyn Error>> {
    let mut args = Args::default();
    let mut iter = env::args().skip(1);
    while let Some(flag) = iter.next() {
        let value = iter
            .next()
            .ok_or_else(|| format!("missing value for {flag}"))?;
        match flag.as_str() {
            "--samples" => args.samples = value.parse()?,
            "--payload-bytes" => args.payload_bytes = value.parse()?,
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

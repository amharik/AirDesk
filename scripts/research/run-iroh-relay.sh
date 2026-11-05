#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE_DIR="$ROOT/research/iroh-probe"
OUT_ROOT="$ROOT/docs/research/runs"
SAMPLES="${AIRDESK_IROH_SAMPLES:-30}"
PAYLOADS=(64 1024 16384)
SERVER="${AIRDESK_IROH_SERVER_SSH:-}"
REMOTE_DIR="${AIRDESK_IROH_REMOTE_DIR:-airdesk-iroh-probe}"
SERVER_IP="${AIRDESK_IROH_SERVER_IP:-}"
ALLOW_NON_MAC="${AIRDESK_RESEARCH_ALLOW_NON_MAC:-0}"
TARGET_DIR="${CARGO_TARGET_DIR:-$PROBE_DIR/target}"
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/airdesk-iroh-build.XXXXXX")"
SERVER_OUT="$(mktemp "${TMPDIR:-/tmp}/airdesk-iroh-server.XXXXXX")"
SERVER_ERR="$(mktemp "${TMPDIR:-/tmp}/airdesk-iroh-server-err.XXXXXX")"
REMOTE_PID_FILE="/tmp/airdesk-iroh-server-$$.pid"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    if [[ -n "$SERVER" ]]; then
      remote_pid="$(ssh -o BatchMode=yes "$SERVER" "cat '$REMOTE_PID_FILE'" 2>/dev/null || true)"
      if [[ -n "$remote_pid" ]]; then
        ssh -o BatchMode=yes "$SERVER" "kill -INT '$remote_pid'" >/dev/null 2>&1 || true
      fi
    fi
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "$SERVER" ]]; then
    ssh -o BatchMode=yes "$SERVER" "rm -f '$REMOTE_PID_FILE'" >/dev/null 2>&1 || true
  fi
  rm -f "$BUILD_LOG" "$SERVER_OUT" "$SERVER_ERR"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" && "$ALLOW_NON_MAC" != "1" ]]; then
  echo "The Iroh network probe requires a macOS client host." >&2
  echo "Set AIRDESK_RESEARCH_ALLOW_NON_MAC=1 only for harness development." >&2
  exit 1
fi

if [[ -z "$SERVER" ]]; then
  echo "Set AIRDESK_IROH_SERVER_SSH to the remote endpoint SSH target." >&2
  exit 1
fi

for tool in cargo git ssh tailscale tar ping; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

if [[ ! -f "$PROBE_DIR/Cargo.toml" ]]; then
  echo "Missing probe manifest: $PROBE_DIR/Cargo.toml" >&2
  exit 1
fi

if [[ ! "$SAMPLES" =~ ^[1-9][0-9]{0,4}$ ]]; then
  echo "Samples must be an integer between 1 and 10000." >&2
  exit 1
fi

if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP="$(ssh -o BatchMode=yes "$SERVER" 'tailscale ip -4 | head -n 1' 2>/dev/null || true)"
fi

echo "syncing probe source to $SERVER:$REMOTE_DIR"
tar -C "$ROOT" -czf - \
  research/iroh-probe/Cargo.toml \
  research/iroh-probe/Cargo.lock \
  research/iroh-probe/src/main.rs \
  | ssh -o BatchMode=yes "$SERVER" "mkdir -p '$REMOTE_DIR' && tar -C '$REMOTE_DIR' -xzf -"

echo "building probe on remote host"
ssh -o BatchMode=yes "$SERVER" \
  ". \"\$HOME/.cargo/env\"; cd \"$REMOTE_DIR/research/iroh-probe\" && cargo build --release --locked" \
  >"$BUILD_LOG" 2>&1
REMOTE_BIN="$REMOTE_DIR/research/iroh-probe/target/release/iroh-probe"
if ! ssh -o BatchMode=yes "$SERVER" "test -x '$REMOTE_BIN'"; then
  echo "Remote probe binary was not produced at $REMOTE_BIN" >&2
  tail -n 80 "$BUILD_LOG" >&2
  exit 1
fi

DATE_STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_ID="$DATE_STAMP-iroh-relay-fallback"
RUN_DIR="$OUT_ROOT/$RUN_ID"
if [[ -e "$RUN_DIR" ]]; then
  RUN_ID="$RUN_ID-$$"
  RUN_DIR="$OUT_ROOT/$RUN_ID"
fi
mkdir -p "$RUN_DIR"

COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
DIRTY="false"
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
  DIRTY="true"
fi
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal -- \
  research/iroh-probe scripts/research/run-iroh-relay.sh research/scenarios/iroh-relay-fallback.json)" ]]; then
  DIRTY="true"
fi
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -r)"
HOST_ARCH="$(uname -m)"
CARGO_VERSION="$(cargo --version)"
CARGO_VERSION="${CARGO_VERSION#cargo }"
CARGO_VERSION="${CARGO_VERSION%% *}"
SERVER_OS="$(ssh -o BatchMode=yes "$SERVER" 'uname -srm')"
SERVER_CARGO_VERSION="$(ssh -o BatchMode=yes "$SERVER" '. "$HOME/.cargo/env"; cargo --version')"
SERVER_CARGO_VERSION="${SERVER_CARGO_VERSION#cargo }"
SERVER_CARGO_VERSION="${SERVER_CARGO_VERSION%% *}"
PING_AVG="$(ping -c 3 "$SERVER_IP" 2>/dev/null | awk -F'/' '/round-trip/ {print $5}' || true)"
if [[ -z "$PING_AVG" ]]; then
  PING_AVG="null"
fi
CLIENT_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
TAILNET_PATH="unknown"
if [[ -n "$CLIENT_IP" ]]; then
  TAILNET_PING_LINE="$(ssh -o BatchMode=yes "$SERVER" \
    "tailscale ping -c 1 '$CLIENT_IP' 2>/dev/null | head -n 1" || true)"
  if [[ "$TAILNET_PING_LINE" == *"via DERP"* ]]; then
    TAILNET_PATH="tailscale-derp"
  elif [[ "$TAILNET_PING_LINE" == *"pong from"* ]]; then
    TAILNET_PATH="tailscale-direct"
  fi
fi

echo "building probe on client host"
CARGO_TARGET_DIR="$TARGET_DIR" cargo build \
  --release \
  --locked \
  --manifest-path "$PROBE_DIR/Cargo.toml" >"$BUILD_LOG" 2>&1

BIN="$TARGET_DIR/release/iroh-probe"
if [[ ! -x "$BIN" ]]; then
  echo "Probe binary was not produced at $BIN" >&2
  tail -n 80 "$BUILD_LOG" >&2
  exit 1
fi

echo "starting relay-backed server"
ssh -o BatchMode=yes "$SERVER" \
  "cd \"$REMOTE_DIR/research/iroh-probe\" && echo \$\$ > '$REMOTE_PID_FILE' && exec ./target/release/iroh-probe --mode server --relay true --bind-addr '0.0.0.0:0'" \
  >"$SERVER_OUT" 2>"$SERVER_ERR" &
SERVER_PID=$!

READY="false"
for _ in $(seq 1 300); do
  if grep -q '"event":"ready"' "$SERVER_OUT" 2>/dev/null; then
    READY="true"
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if [[ "$READY" != "true" ]]; then
  echo "Remote Iroh server did not become ready." >&2
  cat "$SERVER_ERR" >&2
  exit 1
fi

PEER_ID="$(sed -n 's/.*"endpoint_id":"\([^"]*\)".*/\1/p' "$SERVER_OUT" | head -n 1)"
PEER_RELAY="$(sed -n 's/.*"relay_url":"\([^"]*\)".*/\1/p' "$SERVER_OUT" | head -n 1)"
if [[ -z "$PEER_ID" || -z "$PEER_RELAY" ]]; then
  echo "Could not parse remote endpoint relay address." >&2
  cat "$SERVER_OUT" >&2
  exit 1
fi

for payload in "${PAYLOADS[@]}"; do
  date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  set +e
  "$BIN" \
    --mode client \
    --network relay \
    --relay true \
    --peer-id "$PEER_ID" \
    --peer-relay "$PEER_RELAY" \
    --samples "$SAMPLES" \
    --payload-bytes "$payload" \
    --run-id "$RUN_ID-${payload}b" \
    --commit "$COMMIT" \
    --dirty "$DIRTY" \
    --date "$date" \
    --host-os "$HOST_OS" \
    --host-arch "$HOST_ARCH" \
    --cargo-version "$CARGO_VERSION" \
    >"$RUN_DIR/${payload}b.json" \
    2>"$RUN_DIR/${payload}b.stderr.log"
  status=$?
  set -e
  if [[ ! -s "$RUN_DIR/${payload}b.json" ]]; then
    echo "No probe result for ${payload} B (status $status)." >&2
    tail -n 80 "$RUN_DIR/${payload}b.stderr.log" >&2
    exit 1
  fi
  if ! grep -q '"pass": true' "$RUN_DIR/${payload}b.json"; then
    echo "Probe run failed for ${payload} B." >&2
    cat "$RUN_DIR/${payload}b.json" >&2
    exit 1
  fi
  if [[ ! -s "$RUN_DIR/${payload}b.stderr.log" ]]; then
    rm -f "$RUN_DIR/${payload}b.stderr.log"
  fi
  echo "$RUN_DIR/${payload}b.json"
done

cat >"$RUN_DIR/run-index.json" <<EOF
{
  "schema_version": 1,
  "run_id": "$RUN_ID",
  "scenario": "T4",
  "scenario_name": "iroh-quic-relay-fallback",
  "candidate": "iroh-quic",
  "transport": "iroh",
  "commit": "$COMMIT",
  "dirty": $DIRTY,
  "samples": $SAMPLES,
  "payloads": [64, 1024, 16384],
  "environment": {
    "host": "macOS $HOST_OS $HOST_ARCH",
    "controller": "cargo $CARGO_VERSION",
    "network": "iroh-relay",
    "ssh_underlay": "$TAILNET_PATH",
    "relay_mode": "default",
    "relay_url": "$PEER_RELAY",
    "server": {
      "role": "remote-linux",
      "os": "$SERVER_OS",
      "controller": "cargo $SERVER_CARGO_VERSION"
    },
    "tailnet_ping_ms": $PING_AVG
  }
}
EOF

echo "run: $RUN_DIR"

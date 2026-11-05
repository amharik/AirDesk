#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE_DIR="$ROOT/research/iroh-probe"
OUT_ROOT="$ROOT/docs/research/runs"
SAMPLES="${AIRDESK_IROH_SAMPLES:-30}"
PAYLOADS=(64 1024 16384)
ALLOW_NON_MAC="${AIRDESK_RESEARCH_ALLOW_NON_MAC:-0}"
TARGET_DIR="${CARGO_TARGET_DIR:-$PROBE_DIR/target}"
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/airdesk-iroh-build.XXXXXX")"
trap 'rm -f "$BUILD_LOG"' EXIT

if [[ "$(uname -s)" != "Darwin" && "$ALLOW_NON_MAC" != "1" ]]; then
  echo "The Iroh probe requires a macOS host. Set AIRDESK_RESEARCH_ALLOW_NON_MAC=1 only for harness development." >&2
  exit 1
fi

for tool in cargo git; do
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

DATE_STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_ID="$DATE_STAMP-iroh-loopback-baseline"
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
  research/iroh-probe scripts/research/run-iroh.sh research/scenarios/iroh-baseline.json)" ]]; then
  DIRTY="true"
fi
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -r)"
HOST_ARCH="$(uname -m)"
CARGO_VERSION="$(cargo --version)"
CARGO_VERSION="${CARGO_VERSION#cargo }"
CARGO_VERSION="${CARGO_VERSION%% *}"

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

for payload in "${PAYLOADS[@]}"; do
  date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  set +e
  "$BIN" \
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
  "scenario_name": "iroh-quic-loopback-baseline",
  "candidate": "iroh-quic",
  "transport": "iroh",
  "commit": "$COMMIT",
  "dirty": $DIRTY,
  "samples": $SAMPLES,
  "payloads": [64, 1024, 16384],
  "environment": {
    "host": "macOS $HOST_OS $HOST_ARCH",
    "controller": "cargo $CARGO_VERSION",
    "network": "loopback",
    "relay_mode": "disabled"
  }
}
EOF

echo "run: $RUN_DIR"

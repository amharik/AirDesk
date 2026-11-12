#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIO="$ROOT/research/scenarios/transport.json"
SAMPLES=0
PAYLOAD_BYTES=0
RUN_ROOT="$ROOT/docs/research/runs"
ALLOW_NON_MAC="${AIRDESK_RESEARCH_ALLOW_NON_MAC:-0}"
BENCH="$ROOT/scripts/research/transport_bench.ts"
CERT_DIR=""

cleanup() {
  if [[ -n "$CERT_DIR" ]]; then
    rm -rf "$CERT_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage: scripts/research/run-transport.sh [options]

Options:
  --scenario PATH      Transport scenario JSON (default: research/scenarios/transport.json)
  --samples N          Override the scenario sample count
  --payload-bytes N    Override the scenario payload size
  --out-dir PATH       Run artifact root (default: docs/research/runs)
  -h, --help           Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    --samples)
      SAMPLES="${2:-}"
      shift 2
      ;;
    --payload-bytes)
      PAYLOAD_BYTES="${2:-}"
      shift 2
      ;;
    --out-dir)
      RUN_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" && "$ALLOW_NON_MAC" != "1" ]]; then
  echo "The transport runner requires a macOS host. Set AIRDESK_RESEARCH_ALLOW_NON_MAC=1 only for harness development." >&2
  exit 1
fi

for tool in deno git openssl swift /usr/bin/time; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

if [[ ! -f "$SCENARIO" ]]; then
  echo "Missing scenario: $SCENARIO" >&2
  exit 1
fi

if [[ ! -f "$BENCH" ]]; then
  echo "Missing benchmark: $BENCH" >&2
  exit 1
fi

if [[ ! "$SAMPLES" =~ ^[0-9]+$ ]]; then
  echo "Samples must be a non-negative integer." >&2
  exit 1
fi

if [[ ! "$PAYLOAD_BYTES" =~ ^[0-9]+$ ]]; then
  echo "Payload bytes must be a non-negative integer." >&2
  exit 1
fi

DATE_STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
SCENARIO_SLUG="$(basename "$SCENARIO" .json)"
PAYLOAD_LABEL=""
if [[ "$PAYLOAD_BYTES" -gt 0 ]]; then
  PAYLOAD_LABEL="-${PAYLOAD_BYTES}b"
fi
RUN_ID="$DATE_STAMP-$SCENARIO_SLUG$PAYLOAD_LABEL"
RUN_DIR="$RUN_ROOT/$RUN_ID"
if [[ -e "$RUN_DIR" ]]; then
  RUN_ID="$RUN_ID-$$"
  RUN_DIR="$RUN_ROOT/$RUN_ID"
fi
mkdir -p "$RUN_DIR"

COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
DIRTY="false"
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
  DIRTY="true"
fi
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -r)"
HOST_ARCH="$(uname -m)"
HOST_MODEL="$(sysctl -n hw.model 2>/dev/null || printf 'unknown')"
CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || printf 'unknown')"
MEMORY_BYTES="$(sysctl -n hw.memsize 2>/dev/null || printf '0')"
DENO_VERSION="$(deno --version | sed -n '1s/^deno \([^ ]*\).*/\1/p')"
CERT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airdesk-research-cert.XXXXXX")"
chmod 700 "$CERT_DIR"
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
  -days 14 -nodes -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -addext "basicConstraints=critical,CA:FALSE" >/dev/null 2>&1
openssl x509 -in "$CERT_DIR/server.crt" -outform der -out "$CERT_DIR/server.der"
chmod 600 "$CERT_DIR/server.key"

set +e
deno run \
  --unstable-net \
  --allow-net=127.0.0.1 \
  --allow-run=swift,/usr/bin/time \
  --allow-read="$SCENARIO" \
  --allow-read="$CERT_DIR" \
  --allow-read="$RUN_DIR" \
  --allow-write="$RUN_DIR" \
  "$BENCH" \
  --scenario "$SCENARIO" \
  --samples "$SAMPLES" \
  --payload-bytes "$PAYLOAD_BYTES" \
  --run-dir "$RUN_DIR" \
  --run-id "$RUN_ID" \
  --commit "$COMMIT" \
  --dirty "$DIRTY" \
  --host-os "$HOST_OS" \
  --host-arch "$HOST_ARCH" \
  --host-model "$HOST_MODEL" \
  --cpu-brand "$CPU_BRAND" \
  --memory-bytes "$MEMORY_BYTES" \
  --deno-version "$DENO_VERSION" \
  --cert "$CERT_DIR/server.crt" \
  --key "$CERT_DIR/server.key" \
  --der "$CERT_DIR/server.der"
OUTCOME=$?
set -e

if [[ ! -s "$RUN_DIR/run.json" ]]; then
  cat > "$RUN_DIR/run.json" <<EOF
{
  "schema_version": 1,
  "run_id": "$RUN_ID",
  "scenario": "unknown",
  "scenario_name": "$SCENARIO_SLUG",
  "candidate": "unknown",
  "commit": "$COMMIT",
  "dirty": $DIRTY,
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "samples": null,
  "metrics": {},
  "failures": [
    "runner failed before writing the raw result"
  ],
  "decision": "hold",
  "pass": false
}
EOF
fi

if [[ ! -s "$RUN_DIR/report.md" ]]; then
  cat > "$RUN_DIR/report.md" <<EOF
# Transport Run

- Run: \`$RUN_ID\`
- Commit: \`$COMMIT\`$([[ "$DIRTY" == "true" ]] && printf ' (dirty)')
- Result: fail

The runner failed before writing a report. Preserve the raw result and inspect stderr.

\`\`\`json
$(cat "$RUN_DIR/run.json")
\`\`\`
EOF
fi

printf 'run: %s\n' "$RUN_DIR/run.json"
printf 'report: %s\n' "$RUN_DIR/report.md"
exit "$OUTCOME"

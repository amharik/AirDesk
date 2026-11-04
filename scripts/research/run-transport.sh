#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIO="$ROOT/research/scenarios/transport.json"
SAMPLES=0
RUN_ROOT="$ROOT/docs/research/runs"
ALLOW_NON_MAC="${AIRDESK_RESEARCH_ALLOW_NON_MAC:-0}"
BENCH="$ROOT/scripts/research/transport_bench.ts"

usage() {
  cat <<'USAGE'
Usage: scripts/research/run-transport.sh [options]

Options:
  --scenario PATH   Transport scenario JSON (default: research/scenarios/transport.json)
  --samples N       Override the scenario sample count
  --out-dir PATH    Run artifact root (default: docs/research/runs)
  -h, --help        Show this help
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

for tool in deno git; do
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

DATE_STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_ID="$DATE_STAMP-transport-harness-smoke"
RUN_DIR="$RUN_ROOT/$RUN_ID"
if [[ -e "$RUN_DIR" ]]; then
  RUN_ID="$RUN_ID-$$"
  RUN_DIR="$RUN_ROOT/$RUN_ID"
fi
mkdir -p "$RUN_DIR"

COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
DIRTY="false"
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  DIRTY="true"
fi
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -r)"
HOST_ARCH="$(uname -m)"
DENO_VERSION="$(deno --version | sed -n '1s/^deno \([^ ]*\).*/\1/p')"

set +e
deno run \
  --allow-net=127.0.0.1 \
  --allow-read="$SCENARIO" \
  --allow-write="$RUN_DIR" \
  "$BENCH" \
  --scenario "$SCENARIO" \
  --samples "$SAMPLES" \
  --run-dir "$RUN_DIR" \
  --run-id "$RUN_ID" \
  --commit "$COMMIT" \
  --dirty "$DIRTY" \
  --host-os "$HOST_OS" \
  --host-arch "$HOST_ARCH" \
  --deno-version "$DENO_VERSION"
OUTCOME=$?
set -e

if [[ ! -s "$RUN_DIR/run.json" ]]; then
  cat > "$RUN_DIR/run.json" <<EOF
{
  "schema_version": 1,
  "run_id": "$RUN_ID",
  "scenario": "S0",
  "scenario_name": "transport-harness-smoke",
  "candidate": "loopback-websocket-baseline",
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
# Transport Harness Smoke

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

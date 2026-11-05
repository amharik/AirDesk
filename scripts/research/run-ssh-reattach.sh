#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT="$ROOT/docs/research/runs"
REMOTE="${AIRDESK_S2_REMOTE_SSH:-}"
REMOTE_HOST="${AIRDESK_S2_REMOTE_HOST:-${REMOTE#*@}}"
REMOTE_USER="${REMOTE%@*}"
REMOTE_PORT="${AIRDESK_S2_REMOTE_PORT:-22}"
SIMULATOR_ID="${AIRDESK_SIMULATOR_ID:-3B46FDF8-1482-4517-99F3-D6EF46A85133}"
BACKGROUND_SECONDS="${AIRDESK_S2_BACKGROUND_SECONDS:-5}"
CYCLES="${AIRDESK_S2_CYCLES:-3}"
ALLOW_NON_MAC="${AIRDESK_RESEARCH_ALLOW_NON_MAC:-0}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/airdesk-s2.XXXXXX")"
KEY_COMMENT="airdesk-s2-$(date -u +%Y%m%dT%H%M%SZ)-$$"
SESSION="airdesk-s2-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TOKEN="s2-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMUX_BIN=""
BUILD_LOG="$WORK/build.log"
TEST_LOG="$WORK/test.log"
RUN_DIR=""

cleanup() {
    if [[ -n "$REMOTE" ]]; then
        if [[ -n "$TMUX_BIN" ]]; then
            ssh -o BatchMode=yes "$REMOTE" \
                "$TMUX_BIN kill-session -t '$SESSION' >/dev/null 2>&1 || true" \
                >/dev/null 2>&1 || true
        fi
        ssh -o BatchMode=yes "$REMOTE" \
            "if [ -f ~/.ssh/authorized_keys ]; then grep -v -F '$KEY_COMMENT' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.airdesk-s2; mv ~/.ssh/authorized_keys.airdesk-s2 ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; fi" \
            >/dev/null 2>&1 || true
    fi
    xcrun simctl spawn "$SIMULATOR_ID" defaults delete com.airdesk.realsshsmoke >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" && "$ALLOW_NON_MAC" != "1" ]]; then
    echo "The SSH reattach baseline requires a macOS controller host." >&2
    echo "Set AIRDESK_RESEARCH_ALLOW_NON_MAC=1 only for harness development." >&2
    exit 1
fi

if [[ -z "$REMOTE" ]]; then
    echo "Set AIRDESK_S2_REMOTE_SSH to the remote SSH target." >&2
    exit 1
fi
if [[ "$REMOTE_USER" == "$REMOTE" ]]; then
    REMOTE_USER="$(id -un)"
fi
if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" ]]; then
    echo "Could not determine the remote SSH host or user." >&2
    exit 1
fi
if [[ ! "$BACKGROUND_SECONDS" =~ ^[1-9][0-9]{0,2}$ ]]; then
    echo "AIRDESK_S2_BACKGROUND_SECONDS must be an integer between 1 and 999." >&2
    exit 1
fi
if [[ ! "$CYCLES" =~ ^[1-9][0-9]{0,2}$ ]]; then
    echo "AIRDESK_S2_CYCLES must be an integer between 1 and 999." >&2
    exit 1
fi

for tool in ssh ssh-keygen ssh-keyscan xcrun xcodebuild python3 git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing required tool: $tool" >&2
        exit 1
    fi
done

TMUX_BIN="$(ssh -o BatchMode=yes "$REMOTE" 'command -v tmux' 2>/dev/null || true)"
if [[ -z "$TMUX_BIN" ]]; then
    echo "tmux is not available on $REMOTE." >&2
    exit 1
fi

HOST_KEY="$(ssh-keyscan -p "$REMOTE_PORT" -t ed25519 "$REMOTE_HOST" 2>/dev/null \
    | awk 'NF >= 2 { print $1, $2; exit }')"
if [[ -z "$HOST_KEY" ]]; then
    echo "Could not read the remote ed25519 host key." >&2
    exit 1
fi

ssh-keygen -q -t ed25519 -N "" -C "$KEY_COMMENT" -f "$WORK/client_key"
PUBLIC_KEY="$(cat "$WORK/client_key.pub")"
ssh -o BatchMode=yes "$REMOTE" \
    "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; printf '%s\n' '$PUBLIC_KEY' >> ~/.ssh/authorized_keys"

PRIVATE_KEY_B64="$(python3 - "$WORK/client_key" <<'PY'
import base64, struct, sys

lines = open(sys.argv[1], "rb").read().splitlines()
body = b"".join(line for line in lines if not line.startswith(b"-"))
data = base64.b64decode(body)
assert data.startswith(b"openssh-key-v1\0")
offset = 15

def read_string(buffer, position):
    length = struct.unpack(">I", buffer[position:position + 4])[0]
    position += 4
    return buffer[position:position + length], position + length

cipher, offset = read_string(data, offset)
kdf, offset = read_string(data, offset)
kdf_options, offset = read_string(data, offset)
key_count = struct.unpack(">I", data[offset:offset + 4])[0]
offset += 4
for _ in range(key_count):
    _, offset = read_string(data, offset)
private_blob, offset = read_string(data, offset)

position = 0
check1 = struct.unpack(">I", private_blob[position:position + 4])[0]
position += 4
check2 = struct.unpack(">I", private_blob[position:position + 4])[0]
position += 4
key_type, position = read_string(private_blob, position)
public_key, position = read_string(private_blob, position)
private_key, position = read_string(private_blob, position)
comment, position = read_string(private_blob, position)
assert check1 == check2 and key_type == b"ssh-ed25519" and len(private_key) == 64
print(base64.b64encode(private_key[:32]).decode())
PY
)"

STARTUP="$TMUX_BIN new -A -s $SESSION"

xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

cd "$ROOT"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
echo "building SSH reattach UI test for $SIMULATOR_ID"
xcodebuild build-for-testing \
    -project AirDesk.xcodeproj \
    -scheme AirDeskUITests \
    -destination "$DESTINATION" \
    CODE_SIGNING_ALLOWED=NO \
    >"$BUILD_LOG" 2>&1 || {
        tail -n 120 "$BUILD_LOG" >&2
        exit 1
    }

xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke host "$REMOTE_HOST"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke port "$REMOTE_PORT"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke username "$REMOTE_USER"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke hostKey "$HOST_KEY"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke privateKey "$PRIVATE_KEY_B64"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke startup "$STARTUP"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke backgroundSeconds "$BACKGROUND_SECONDS"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke cycles "$CYCLES"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke token "$TOKEN"

echo "running S2 reattach test against $REMOTE"
set +e
xcodebuild test-without-building \
    -project AirDesk.xcodeproj \
    -scheme AirDeskUITests \
    -destination "$DESTINATION" \
    -only-testing:AirDeskUITests/RemoteSSHReattachTests/testRemoteSSHReattachesAfterBackground \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    >"$TEST_LOG" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
    tail -n 160 "$TEST_LOG" >&2
    exit "$STATUS"
fi

DATE_STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_ID="$DATE_STAMP-ssh-reattach-baseline"
RUN_DIR="$OUT_ROOT/$RUN_ID"
if [[ -e "$RUN_DIR" ]]; then
    RUN_ID="$RUN_ID-$$"
    RUN_DIR="$OUT_ROOT/$RUN_ID"
fi
mkdir -p "$RUN_DIR"

grep -E 'AIRDESK_S2_|Test Suite|Test Case|error:' "$TEST_LOG" >"$RUN_DIR/test-summary.log" || true

COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
DIRTY="false"
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
    DIRTY="true"
fi
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -r)"
HOST_ARCH="$(uname -m)"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//')"
SIMULATOR_NAME="$(xcrun simctl list devices available | awk -v id="$SIMULATOR_ID" 'index($0, id) { sub(/^[[:space:]]*/, ""); sub(/ \([0-9A-F-]+\)$/, ""); print; exit }')"
REMOTE_OS="$(ssh -o BatchMode=yes "$REMOTE" 'uname -srm')"
REMOTE_TMUX_VERSION="$(ssh -o BatchMode=yes "$REMOTE" "$TMUX_BIN -V")"
REMOTE_ID="$(ssh -o BatchMode=yes "$REMOTE" 'id -un')"
PING_AVG="$(ping -c 3 "$REMOTE_HOST" 2>/dev/null | awk -F'/' '/round-trip/ {print $5}' || true)"
if [[ -z "$PING_AVG" ]]; then
    PING_AVG="null"
fi
TAILNET_PATH="unknown"
TAILNET_PING=""
if command -v tailscale >/dev/null 2>&1; then
    TAILNET_PING="$(tailscale ping -c 1 "$REMOTE_HOST" 2>/dev/null | head -n 1 || true)"
    if [[ "$TAILNET_PING" == *"via DERP"* ]]; then
        TAILNET_PATH="tailscale-derp"
    elif [[ "$TAILNET_PING" == *"pong from"* ]]; then
        TAILNET_PATH="tailscale-direct"
    fi
fi

export S2_RUN_ID="$RUN_ID"
export S2_RUN_DIR="$RUN_DIR"
export S2_TEST_LOG="$TEST_LOG"
export S2_COMMIT="$COMMIT"
export S2_DIRTY="$DIRTY"
export S2_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export S2_HOST_OS="$HOST_OS"
export S2_HOST_ARCH="$HOST_ARCH"
export S2_XCODE_VERSION="$XCODE_VERSION"
export S2_SIMULATOR_NAME="$SIMULATOR_NAME"
export S2_SIMULATOR_ID="$SIMULATOR_ID"
export S2_REMOTE="$REMOTE"
export S2_REMOTE_OS="$REMOTE_OS"
export S2_REMOTE_TMUX="$REMOTE_TMUX_VERSION"
export S2_REMOTE_USER="$REMOTE_ID"
export S2_REMOTE_HOST="$REMOTE_HOST"
export S2_PING_AVG="$PING_AVG"
export S2_TAILNET_PATH="$TAILNET_PATH"
export S2_TAILNET_PING="$TAILNET_PING"
export S2_BACKGROUND_SECONDS="$BACKGROUND_SECONDS"
export S2_CYCLES="$CYCLES"
export S2_TOKEN="$TOKEN"

python3 - <<'PY'
import json, math, os, re, statistics

run_dir = os.environ["S2_RUN_DIR"]
log = open(os.environ["S2_TEST_LOG"], encoding="utf-8", errors="replace").read()
cycles = int(os.environ["S2_CYCLES"])
values = [int(value) for value in re.findall(r"AIRDESK_S2_CYCLE_REATTACH_MS=(\d+)", log)]
survived = len(re.findall(r"AIRDESK_S2_CYCLE_PROCESS_SURVIVED=true", log))
truthful = len(re.findall(r"AIRDESK_S2_CYCLE_TRANSCRIPT_TRUTHFUL=true", log))
done = "AIRDESK_S2_DONE=true" in log

if len(values) != cycles or survived != cycles or truthful != cycles or not done:
    raise SystemExit(
        f"incomplete S2 log: cycles={len(values)}/{cycles} "
        f"survived={survived}/{cycles} truthful={truthful}/{cycles} done={done}"
    )

def percentile(sorted_values, p):
    index = max(0, min(len(sorted_values) - 1, math.ceil(p / 100 * len(sorted_values)) - 1))
    return sorted_values[index]

ordered = sorted(values)
metrics = {
    "reattach_ms": {
        "p50": percentile(ordered, 50),
        "p95": percentile(ordered, 95),
        "p99": percentile(ordered, 99),
        "min": ordered[0],
        "max": ordered[-1],
        "values": values,
    },
    "process_survived": True,
    "transcript_truthful": True,
}

environment = {
    "controller": f"{os.environ['S2_SIMULATOR_NAME']} / iOS 18.6 simulator",
    "simulator_id": os.environ["S2_SIMULATOR_ID"],
    "xcode": os.environ["S2_XCODE_VERSION"],
    "host": f"macOS {os.environ['S2_HOST_OS']} {os.environ['S2_HOST_ARCH']}",
    "server": os.environ["S2_REMOTE_OS"],
    "server_user": os.environ["S2_REMOTE_USER"],
    "server_tmux": os.environ["S2_REMOTE_TMUX"],
    "network": "tailnet",
    "underlay": os.environ["S2_TAILNET_PATH"],
    "underlay_probe": os.environ["S2_TAILNET_PING"],
    "ping_avg_ms": None if os.environ["S2_PING_AVG"] == "null" else float(os.environ["S2_PING_AVG"]),
    "background_seconds": int(os.environ["S2_BACKGROUND_SECONDS"]),
}

result = {
    "schema_version": 1,
    "scenario": "S2",
    "candidate": "ssh-tmux-baseline",
    "transport": "ssh",
    "run_id": os.environ["S2_RUN_ID"],
    "commit": os.environ["S2_COMMIT"],
    "dirty": os.environ["S2_DIRTY"] == "true",
    "date": os.environ["S2_DATE"],
    "samples": cycles,
    "environment": environment,
    "metrics": metrics,
    "failures": [],
    "pass": {
        "process_survived": True,
        "transcript_truthful": True,
        "reattach_ms": True,
    },
}

with open(os.path.join(run_dir, "run.json"), "w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2)
    handle.write("\n")

report = f"""# S2 SSH/tmux Reattach Baseline

- **Run:** `{os.environ['S2_RUN_ID']}`
- **Commit:** `{os.environ['S2_COMMIT']}` (dirty: `{os.environ['S2_DIRTY']}`)
- **Date:** {os.environ['S2_DATE']}
- **Controller:** {environment['controller']}
- **Host:** {environment['host']}
- **Server:** {environment['server']} (`{environment['server_user']}`, `{environment['server_tmux']}`)
- **Network:** {environment['network']}; underlay `{environment['underlay']}`

## Result

| Metric | Value |
| --- | --- |
| Samples | {cycles} |
| Reattach p50 | {metrics['reattach_ms']['p50']} ms |
| Reattach p95 | {metrics['reattach_ms']['p95']} ms |
| Reattach p99 | {metrics['reattach_ms']['p99']} ms |
| Reattach min / max | {metrics['reattach_ms']['min']} / {metrics['reattach_ms']['max']} ms |
| Remote process survived | yes, {survived}/{cycles} |
| Transcript truthful | yes, {truthful}/{cycles} |

The scenario armed a delayed remote marker, backgrounded the app to drop the SSH session, returned to the foreground, waited for a fresh `terminal.ssh.ready`, verified the delayed marker, and then confirmed new input reached the reattached shell.

## Scope

This is a simulator-to-tailnet baseline. It does not prove physical-device background behavior, a second controller device, a direct-underlay path, or app termination recovery. The Tailscale underlay is recorded separately from the SSH/tmux session.

Raw evidence: `run.json`, `test-summary.log`.
"""

with open(os.path.join(run_dir, "report.md"), "w", encoding="utf-8") as handle:
    handle.write(report)
PY

echo "$RUN_DIR"

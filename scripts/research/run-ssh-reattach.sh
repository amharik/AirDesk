#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT="$ROOT/docs/research/runs"
REMOTE="${AIRDESK_S2_REMOTE_SSH:-}"
REMOTE_HOST="${AIRDESK_S2_REMOTE_HOST:-${REMOTE#*@}}"
REMOTE_USER="${REMOTE%@*}"
REMOTE_PORT="${AIRDESK_S2_REMOTE_PORT:-22}"
SIMULATOR_ID="${AIRDESK_SIMULATOR_ID:-3B46FDF8-1482-4517-99F3-D6EF46A85133}"
SIMULATOR_ID_B="${AIRDESK_S2_SECONDARY_SIMULATOR_ID:-DB9D5BBC-3996-440A-8641-4A236F42A0E0}"
MODE="${AIRDESK_S2_MODE:-background}"
BACKGROUND_SECONDS="${AIRDESK_S2_BACKGROUND_SECONDS:-5}"
TERMINATION_SECONDS="${AIRDESK_S2_TERMINATION_SECONDS:-2}"
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
            ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" \
                "$TMUX_BIN kill-session -t '$SESSION' >/dev/null 2>&1 || true" \
                >/dev/null 2>&1 || true
        fi
        ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" \
            "if [ -f ~/.ssh/authorized_keys ]; then grep -v -F '$KEY_COMMENT' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.airdesk-s2; mv ~/.ssh/authorized_keys.airdesk-s2 ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; fi" \
            >/dev/null 2>&1 || true
    fi
    xcrun simctl spawn "$SIMULATOR_ID" defaults delete com.airdesk.realsshsmoke >/dev/null 2>&1 || true
    if [[ "$SIMULATOR_ID_B" != "$SIMULATOR_ID" ]]; then
        xcrun simctl spawn "$SIMULATOR_ID_B" defaults delete com.airdesk.realsshsmoke >/dev/null 2>&1 || true
    fi
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
if [[ ! "$TERMINATION_SECONDS" =~ ^[1-9][0-9]{0,2}$ ]]; then
    echo "AIRDESK_S2_TERMINATION_SECONDS must be an integer between 1 and 999." >&2
    exit 1
fi

case "$MODE" in
    background)
        TEST_METHOD="testRemoteSSHReattachesAfterBackground"
        RUN_SUFFIX="ssh-reattach-baseline"
        SCENARIO_NAME="ssh-tmux-reattach-baseline"
        ;;
    termination)
        TEST_METHOD="testRemoteSSHReattachesAfterTermination"
        RUN_SUFFIX="ssh-termination-baseline"
        SCENARIO_NAME="ssh-tmux-termination-baseline"
        ;;
    second-device)
        TEST_METHOD="testRemoteSSHSecondDevicePrimary"
        RUN_SUFFIX="ssh-second-device-baseline"
        SCENARIO_NAME="ssh-tmux-second-device-baseline"
        ;;
    *)
        echo "AIRDESK_S2_MODE must be 'background', 'termination' or 'second-device'." >&2
        exit 1
        ;;
esac

if [[ "$MODE" == "second-device" && "$SIMULATOR_ID_B" == "$SIMULATOR_ID" ]]; then
    echo "AIRDESK_S2_SECONDARY_SIMULATOR_ID must differ from AIRDESK_SIMULATOR_ID." >&2
    exit 1
fi

for tool in ssh ssh-keygen ssh-keyscan xcrun xcodebuild python3 git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing required tool: $tool" >&2
        exit 1
    fi
done

TMUX_BIN="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" 'command -v tmux' 2>/dev/null || true)"
if [[ -z "$TMUX_BIN" ]]; then
    echo "tmux is not available on $REMOTE." >&2
    exit 1
fi

HOST_KEY="$(ssh-keyscan -p "$REMOTE_PORT" -t ed25519 "$REMOTE_HOST" 2>/dev/null \
    | awk '$2 == "ssh-ed25519" { print $2, $3; exit }')"
if [[ -z "$HOST_KEY" ]]; then
    echo "Could not read the remote ed25519 host key." >&2
    exit 1
fi

ssh-keygen -q -t ed25519 -N "" -C "$KEY_COMMENT" -f "$WORK/client_key"
PUBLIC_KEY="$(cat "$WORK/client_key.pub")"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" \
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

STARTUP="$TMUX_BIN new -A -s $SESSION 'i=0; while :; do i=\$((i+1)); echo S2-REMOTE-SURVIVED-$TOKEN-\$i; sleep 2; done'"

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
    ENABLE_ON_DEMAND_RESOURCES=NO \
    >"$BUILD_LOG" 2>&1 || {
        tail -n 120 "$BUILD_LOG" >&2
        exit 1
    }

write_defaults() {
    local simulator="$1"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke host "$REMOTE_HOST"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke port "$REMOTE_PORT"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke username "$REMOTE_USER"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke hostKey "$HOST_KEY"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke privateKey "$PRIVATE_KEY_B64"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke startup -string "$STARTUP"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke backgroundSeconds "$BACKGROUND_SECONDS"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke terminationSeconds "$TERMINATION_SECONDS"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke cycles "$CYCLES"
    xcrun simctl spawn "$simulator" defaults write com.airdesk.realsshsmoke token "$TOKEN"
}

if [[ "$MODE" == "second-device" ]]; then
    write_defaults "$SIMULATOR_ID"
    PRIMARY_LOG="$WORK/primary.log"
    SECONDARY_LOG="$WORK/secondary.log"

    echo "running S2 primary controller on $SIMULATOR_ID"
    set +e
    xcodebuild test-without-building \
        -project AirDesk.xcodeproj \
        -scheme AirDeskUITests \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -only-testing:AirDeskUITests/RemoteSSHReattachTests/testRemoteSSHSecondDevicePrimary \
        -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO \
        >"$PRIMARY_LOG" 2>&1
    PRIMARY_STATUS=$?
    set -e
    if [[ "$PRIMARY_STATUS" -ne 0 ]]; then
        tail -n 160 "$PRIMARY_LOG" >&2
        exit "$PRIMARY_STATUS"
    fi

    PRIMARY_MARKER="$(sed -n 's/.*AIRDESK_S2_PRIMARY_MARKER=\([0-9][0-9]*\).*/\1/p' "$PRIMARY_LOG" | tail -n 1)"
    if [[ -z "$PRIMARY_MARKER" ]]; then
        echo "Primary controller did not report a heartbeat marker." >&2
        exit 1
    fi

    xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$SIMULATOR_ID_B" >/dev/null 2>&1 || true
    xcrun simctl boot "$SIMULATOR_ID_B" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$SIMULATOR_ID_B" -b
    sleep 10
    write_defaults "$SIMULATOR_ID_B"
    xcrun simctl spawn "$SIMULATOR_ID_B" defaults write com.airdesk.realsshsmoke baselineMarker "$PRIMARY_MARKER"

    echo "running S2 secondary controller on $SIMULATOR_ID_B (baseline $PRIMARY_MARKER)"
    SECONDARY_ATTEMPTS=1
    set +e
    xcodebuild test-without-building \
        -project AirDesk.xcodeproj \
        -scheme AirDeskUITests \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID_B" \
        -only-testing:AirDeskUITests/RemoteSSHReattachTests/testRemoteSSHSecondDeviceSecondary \
        -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO \
        >"$SECONDARY_LOG" 2>&1
    SECONDARY_STATUS=$?
    set -e
    if [[ "$SECONDARY_STATUS" -ne 0 ]] && grep -q "Timed out waiting for AX loaded notification" "$SECONDARY_LOG"; then
        cp "$SECONDARY_LOG" "$WORK/secondary.attempt1.log"
        echo "secondary UI test could not initialize; retrying once" >&2
        SECONDARY_ATTEMPTS=2
        sleep 10
        set +e
        xcodebuild test-without-building \
            -project AirDesk.xcodeproj \
            -scheme AirDeskUITests \
            -destination "platform=iOS Simulator,id=$SIMULATOR_ID_B" \
            -only-testing:AirDeskUITests/RemoteSSHReattachTests/testRemoteSSHSecondDeviceSecondary \
            -parallel-testing-enabled NO \
            CODE_SIGNING_ALLOWED=NO \
            >"$SECONDARY_LOG" 2>&1
        SECONDARY_STATUS=$?
        set -e
    fi
    if [[ "$SECONDARY_STATUS" -ne 0 ]]; then
        tail -n 160 "$SECONDARY_LOG" >&2
        exit "$SECONDARY_STATUS"
    fi

    SECONDARY_CONNECT_MS="$(sed -n 's/.*AIRDESK_S2_SECONDARY_CONNECT_MS=\([0-9][0-9]*\).*/\1/p' "$SECONDARY_LOG" | tail -n 1)"
    SECONDARY_MARKER="$(sed -n 's/.*AIRDESK_S2_SECONDARY_MARKER=\([0-9][0-9]*\).*/\1/p' "$SECONDARY_LOG" | tail -n 1)"
    if [[ -z "$SECONDARY_CONNECT_MS" || -z "$SECONDARY_MARKER" ]]; then
        echo "Secondary controller did not report connect time or heartbeat marker." >&2
        exit 1
    fi
    if (( SECONDARY_MARKER <= PRIMARY_MARKER )); then
        echo "Secondary heartbeat marker did not advance past the primary baseline." >&2
        exit 1
    fi
    {
        echo "PRIMARY"
        cat "$PRIMARY_LOG"
        if [[ -f "$WORK/secondary.attempt1.log" ]]; then
            echo "SECONDARY-ATTEMPT-1"
            cat "$WORK/secondary.attempt1.log"
        fi
        echo "SECONDARY"
        cat "$SECONDARY_LOG"
    } >"$TEST_LOG"
else
    write_defaults "$SIMULATOR_ID"

    echo "running S2 reattach test against $REMOTE"
    set +e
    xcodebuild test-without-building \
        -project AirDesk.xcodeproj \
        -scheme AirDeskUITests \
        -destination "$DESTINATION" \
        -only-testing:AirDeskUITests/RemoteSSHReattachTests/$TEST_METHOD \
        -parallel-testing-enabled NO \
        CODE_SIGNING_ALLOWED=NO \
        >"$TEST_LOG" 2>&1
    STATUS=$?
    set -e

    if [[ "$STATUS" -ne 0 ]]; then
        tail -n 160 "$TEST_LOG" >&2
        exit "$STATUS"
    fi
fi

DATE_STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
RUN_ID="$DATE_STAMP-$RUN_SUFFIX"
RUN_DIR="$OUT_ROOT/$RUN_ID"
if [[ -e "$RUN_DIR" ]]; then
    RUN_ID="$RUN_ID-$$"
    RUN_DIR="$OUT_ROOT/$RUN_ID"
fi
mkdir -p "$RUN_DIR"

grep -E 'AIRDESK_S2_|Test Suite|Test Case|error:|^PRIMARY$|^SECONDARY$|^SECONDARY-ATTEMPT-1$' "$TEST_LOG" >"$RUN_DIR/test-summary.log" || true

COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
DIRTY="false"
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
    DIRTY="true"
fi
HOST_OS="$(sw_vers -productVersion 2>/dev/null || uname -r)"
HOST_ARCH="$(uname -m)"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//')"
SIMULATOR_NAME="$(xcrun simctl list devices available | awk -v id="$SIMULATOR_ID" 'index($0, id) { sub(/^[[:space:]]*/, ""); sub(/ \([0-9A-F-]+\)( \((Booted|Shutdown)\))?$/, ""); print; exit }')"
SIMULATOR_NAME_B="$(xcrun simctl list devices available | awk -v id="$SIMULATOR_ID_B" 'index($0, id) { sub(/^[[:space:]]*/, ""); sub(/ \([0-9A-F-]+\)( \((Booted|Shutdown)\))?$/, ""); print; exit }')"
REMOTE_OS="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" 'uname -srm')"
REMOTE_TMUX_VERSION="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "$TMUX_BIN -V")"
REMOTE_ID="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" 'id -un')"
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
export S2_SIMULATOR_NAME_B="$SIMULATOR_NAME_B"
export S2_SIMULATOR_ID_B="$SIMULATOR_ID_B"
export S2_PRIMARY_MARKER="${PRIMARY_MARKER:-}"
export S2_SECONDARY_MARKER="${SECONDARY_MARKER:-}"
export S2_SECONDARY_CONNECT_MS="${SECONDARY_CONNECT_MS:-}"
export S2_SECONDARY_ATTEMPTS="${SECONDARY_ATTEMPTS:-1}"
export S2_REMOTE="$REMOTE"
export S2_REMOTE_OS="$REMOTE_OS"
export S2_REMOTE_TMUX="$REMOTE_TMUX_VERSION"
export S2_REMOTE_USER="$REMOTE_ID"
export S2_REMOTE_HOST="$REMOTE_HOST"
export S2_PING_AVG="$PING_AVG"
export S2_TAILNET_PATH="$TAILNET_PATH"
export S2_TAILNET_PING="$TAILNET_PING"
export S2_MODE="$MODE"
export S2_SCENARIO_NAME="$SCENARIO_NAME"
export S2_BACKGROUND_SECONDS="$BACKGROUND_SECONDS"
export S2_TERMINATION_SECONDS="$TERMINATION_SECONDS"
export S2_CYCLES="$CYCLES"
export S2_TOKEN="$TOKEN"

python3 - <<'PY'
import json, math, os, re, statistics, sys

run_dir = os.environ["S2_RUN_DIR"]
log = open(os.environ["S2_TEST_LOG"], encoding="utf-8", errors="replace").read()
cycles = int(os.environ["S2_CYCLES"])
values = [int(value) for value in re.findall(r"AIRDESK_S2_CYCLE_REATTACH_MS=(\d+)", log)]
survived = len(re.findall(r"AIRDESK_S2_CYCLE_PROCESS_SURVIVED=true", log))
truthful = len(re.findall(r"AIRDESK_S2_CYCLE_TRANSCRIPT_TRUTHFUL=true", log))
done = "AIRDESK_S2_DONE=true" in log
mode = os.environ["S2_MODE"]
if mode == "second-device":
    primary_marker = int(os.environ["S2_PRIMARY_MARKER"])
    secondary_marker = int(os.environ["S2_SECONDARY_MARKER"])
    secondary_connect_ms = int(os.environ["S2_SECONDARY_CONNECT_MS"])
    secondary_attempts = int(os.environ["S2_SECONDARY_ATTEMPTS"])
    primary_ready = "AIRDESK_S2_PRIMARY_READY=true" in log
    secondary_ready = "AIRDESK_S2_SECONDARY_READY=true" in log
    done = log.count("AIRDESK_S2_DONE=true") >= 2
    if not primary_ready or not secondary_ready or not done or secondary_marker <= primary_marker:
        raise SystemExit(
            "incomplete second-device log: "
            f"primary_ready={primary_ready} secondary_ready={secondary_ready} "
            f"done={done} primary={primary_marker} secondary={secondary_marker}"
        )

    environment = {
        "controller_a": f"{os.environ['S2_SIMULATOR_NAME']} / iOS 18.6 simulator",
        "simulator_id_a": os.environ["S2_SIMULATOR_ID"],
        "controller_b": f"{os.environ['S2_SIMULATOR_NAME_B']} / iOS 18.6 simulator",
        "simulator_id_b": os.environ["S2_SIMULATOR_ID_B"],
        "xcode": os.environ["S2_XCODE_VERSION"],
        "host": f"macOS {os.environ['S2_HOST_OS']} {os.environ['S2_HOST_ARCH']}",
        "server": os.environ["S2_REMOTE_OS"],
        "server_user": os.environ["S2_REMOTE_USER"],
        "server_tmux": os.environ["S2_REMOTE_TMUX"],
        "network": "tailnet",
        "underlay": os.environ["S2_TAILNET_PATH"],
        "underlay_probe": os.environ["S2_TAILNET_PING"],
        "ping_avg_ms": None if os.environ["S2_PING_AVG"] == "null" else float(os.environ["S2_PING_AVG"]),
        "mode": mode,
    }
    metrics = {
        "secondary_connect_ms": secondary_connect_ms,
        "secondary_attempts": secondary_attempts,
        "primary_marker": primary_marker,
        "secondary_marker": secondary_marker,
        "heartbeat_advanced": secondary_marker > primary_marker,
        "process_survived": True,
        "transcript_truthful": True,
    }
    result = {
        "schema_version": 1,
        "scenario": "S2",
        "scenario_name": os.environ["S2_SCENARIO_NAME"],
        "candidate": "ssh-tmux-baseline",
        "transport": "ssh",
        "run_id": os.environ["S2_RUN_ID"],
        "commit": os.environ["S2_COMMIT"],
        "dirty": os.environ["S2_DIRTY"] == "true",
        "date": os.environ["S2_DATE"],
        "samples": 1,
        "failure_injection": ["primary-controller-terminated", "second-device-takeover"],
        "environment": environment,
        "metrics": metrics,
        "failures": [],
        "pass": {
            "process_survived": True,
            "transcript_truthful": True,
            "heartbeat_advanced": True,
            "secondary_connect_ms": True,
        },
    }
    with open(os.path.join(run_dir, "run.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)
        handle.write("\n")

    report = f"""# S2 SSH/tmux Second-Device Handoff Baseline

- **Run:** `{os.environ['S2_RUN_ID']}`
- **Commit:** `{os.environ['S2_COMMIT']}` (dirty: `{os.environ['S2_DIRTY']}`)
- **Date:** {os.environ['S2_DATE']}
- **Primary controller:** {environment['controller_a']} (`{environment['simulator_id_a']}`)
- **Secondary controller:** {environment['controller_b']} (`{environment['simulator_id_b']}`)
- **Host:** {environment['host']}
- **Server:** {environment['server']} (`{environment['server_user']}`, {environment['server_tmux']})
- **Network:** {environment['network']}; underlay `{environment['underlay']}`

## Result

| Metric | Value |
| --- | --- |
| Primary heartbeat marker | {primary_marker} |
| Secondary heartbeat marker | {secondary_marker} |
| Heartbeat advanced after handoff | yes |
| Secondary cold connect | {secondary_connect_ms} ms |
| Secondary test attempts | {secondary_attempts} |
| Remote process survived | yes |
| Transcript truthful | yes |

The primary simulator attached to a unique tmux session, observed the heartbeat and terminated its app. The secondary simulator then attached to the same session, observed a later heartbeat marker and verified a fresh `terminal.ssh.ready`. `secondary_connect_ms` covers the full cold recovery from `app.launch()` through app startup, preview presentation, SSH attach and the ready event.

## Scope

This is a two-simulator handoff on one Mac, not two physical devices and not a simultaneous two-controller session. It does not prove direct-underlay behavior, long-idle survival or key hygiene across a real handoff.

Raw evidence: `run.json`, `test-summary.log`.
"""
    with open(os.path.join(run_dir, "report.md"), "w", encoding="utf-8") as handle:
        handle.write(report)
    sys.exit(0)


if len(values) != cycles or survived != cycles or truthful != cycles or not done:
    raise SystemExit(
        f"incomplete S2 log: cycles={len(values)}/{cycles} "
        f"survived={survived}/{cycles} truthful={truthful}/{cycles} done={done}"
    )

def percentile(sorted_values, p):
    index = max(0, min(len(sorted_values) - 1, math.ceil(p / 100 * len(sorted_values)) - 1))
    return sorted_values[index]

ordered = sorted(values)
mode = os.environ["S2_MODE"]
metric_key = "relaunch_ms" if mode == "termination" else "reattach_ms"
metrics = {
    metric_key: {
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
    "mode": mode,
    "background_seconds": int(os.environ["S2_BACKGROUND_SECONDS"]) if mode == "background" else None,
    "termination_seconds": int(os.environ["S2_TERMINATION_SECONDS"]) if mode == "termination" else None,
}

result = {
    "schema_version": 1,
    "scenario": "S2",
    "scenario_name": os.environ["S2_SCENARIO_NAME"],
    "candidate": "ssh-tmux-baseline",
    "transport": "ssh",
    "run_id": os.environ["S2_RUN_ID"],
    "commit": os.environ["S2_COMMIT"],
    "dirty": os.environ["S2_DIRTY"] == "true",
    "date": os.environ["S2_DATE"],
    "samples": cycles,
    "failure_injection": ["app-termination"] if mode == "termination" else ["app-background-and-ssh-drop"],
    "environment": environment,
    "metrics": metrics,
    "failures": [],
    "pass": {
        "process_survived": True,
        "transcript_truthful": True,
        metric_key: True,
    },
}

with open(os.path.join(run_dir, "run.json"), "w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2)
    handle.write("\n")

if mode == "termination":
    title = "S2 SSH/tmux Termination Recovery Baseline"
    label = "Relaunch recovery"
    action = (
        "terminated the app process, waited, relaunched it, reopened the preview, "
        "waited for a fresh `terminal.ssh.ready`, and verified a new heartbeat marker arrived after each relaunch"
    )
    scope = (
        "`relaunch_ms` covers the full cold recovery from `app.launch()` through app startup, preview presentation, "
        "SSH reconnect and the first fresh ready event; it is not a transport-only reconnect measurement. "
        "This is a simulator-to-tailnet baseline. It does not prove physical-device termination "
        "behavior, a second controller device or a direct-underlay path; background behavior is covered separately."
    )
else:
    title = "S2 SSH/tmux Reattach Baseline"
    label = "Reattach"
    action = (
        "backgrounded the app to drop the SSH session, returned to the foreground, "
        "waited for a fresh `terminal.ssh.ready`, and verified a new heartbeat marker arrived after each reattach"
    )
    scope = (
        "This is a simulator-to-tailnet baseline. It does not prove physical-device background behavior, "
        "a second controller device, a direct-underlay path, or app termination recovery. "
        "The Tailscale underlay is recorded separately from the SSH/tmux session."
    )

report = f"""# {title}

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
| {label} p50 | {metrics[metric_key]['p50']} ms |
| {label} p95 | {metrics[metric_key]['p95']} ms |
| {label} p99 | {metrics[metric_key]['p99']} ms |
| {label} min / max | {metrics[metric_key]['min']} / {metrics[metric_key]['max']} ms |
| Remote process survived | yes, {survived}/{cycles} |
| Transcript truthful | yes, {truthful}/{cycles} |

The scenario started a remote heartbeat inside the tmux session and {action}.

## Scope

{scope}

Raw evidence: `run.json`, `test-summary.log`.
"""

with open(os.path.join(run_dir, "report.md"), "w", encoding="utf-8") as handle:
    handle.write(report)
PY

echo "$RUN_DIR"

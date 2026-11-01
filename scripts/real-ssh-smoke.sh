#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AIRDESK_SSH_SMOKE_PORT:-22222}"
BIND_HOST="${AIRDESK_SSH_BIND_HOST:-127.0.0.1}"
SSH_HOST="${AIRDESK_SSH_HOST:-$BIND_HOST}"
SIMULATOR_ID="${AIRDESK_SIMULATOR_ID:-F8348DD0-C13D-4A5F-A4C3-4D15589D7DDE}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/airdesk-sshd.XXXXXX")"
SSHD_PID=""
TMUX_BIN="$(command -v tmux || true)"
TMUX_SESSION=""

cleanup() {
    if [[ -n "$TMUX_BIN" && -n "$TMUX_SESSION" ]]; then
        "$TMUX_BIN" kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true
    fi
    xcrun simctl spawn "$SIMULATOR_ID" defaults delete com.airdesk.realsshsmoke >/dev/null 2>&1 || true
    if [[ -n "$SSHD_PID" ]]; then
        kill "$SSHD_PID" 2>/dev/null || true
        wait "$SSHD_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is already in use." >&2
    exit 1
fi

ssh-keygen -q -t ed25519 -N "" -f "$WORK/client_key"
ssh-keygen -q -t ed25519 -N "" -f "$WORK/host_key"
cp "$WORK/client_key.pub" "$WORK/authorized_keys"
chmod 700 "$WORK"
chmod 600 "$WORK/authorized_keys" "$WORK/host_key" "$WORK/client_key"

cat > "$WORK/sshd_config" <<CONFIG
Port $PORT
ListenAddress $BIND_HOST
HostKey $WORK/host_key
PidFile $WORK/sshd.pid
AuthorizedKeysFile $WORK/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
UsePAM no
StrictModes no
AllowUsers $(id -un)
LogLevel ERROR
CONFIG

/usr/sbin/sshd -f "$WORK/sshd_config" -E "$WORK/sshd.log"
sleep 1
SSHD_PID="$(cat "$WORK/sshd.pid")"

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

HOST_KEY="$(cut -d' ' -f1,2 "$WORK/host_key.pub")"
STARTUP="${AIRDESK_SSH_STARTUP:-}"
if [[ -z "$STARTUP" && -n "$TMUX_BIN" ]]; then
    TMUX_SESSION="airdesk-smoke-$$"
    STARTUP="$TMUX_BIN new -A -s $TMUX_SESSION"
fi
export AIRDESK_SSH_HOST="$SSH_HOST"
export AIRDESK_SSH_PORT="$PORT"
export AIRDESK_SSH_USERNAME="$(id -un)"
export AIRDESK_SSH_HOST_KEY="$HOST_KEY"
export AIRDESK_SSH_PRIVATE_KEY_B64="$PRIVATE_KEY_B64"
export AIRDESK_SSH_STARTUP="$STARTUP"

xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

cd "$ROOT"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
fi

DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
xcodebuild build-for-testing \
    -project AirDesk.xcodeproj \
    -scheme AirDeskUITests \
    -destination "$DESTINATION" \
    CODE_SIGNING_ALLOWED=NO

xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke host "$AIRDESK_SSH_HOST"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke port "$AIRDESK_SSH_PORT"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke username "$AIRDESK_SSH_USERNAME"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke hostKey "$AIRDESK_SSH_HOST_KEY"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke privateKey "$AIRDESK_SSH_PRIVATE_KEY_B64"
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.realsshsmoke startup "$AIRDESK_SSH_STARTUP"

xcodebuild test-without-building \
    -project AirDesk.xcodeproj \
    -scheme AirDeskUITests \
    -destination "$DESTINATION" \
    -only-testing:AirDeskUITests/RealSSHTerminalTests \
    CODE_SIGNING_ALLOWED=NO

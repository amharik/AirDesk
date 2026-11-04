#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SIMULATOR_ID="${AIRDESK_SIMULATOR_ID:-3B46FDF8-1482-4517-99F3-D6EF46A85133}"
SAMPLES="${AIRDESK_WEBRTC_SAMPLES:-30}"
PAYLOADS=(64 1024 16384)
RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-webrtc-ios-baseline"
OUT_DIR="$ROOT/docs/research/runs/$RUN_ID"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airdesk-webrtc-ios.XXXXXX")"

cleanup() {
  xcrun simctl spawn "$SIMULATOR_ID" defaults delete com.airdesk.webrtcprobe >/dev/null 2>&1 || true
  rm -rf "$LOG_DIR"
}
trap cleanup EXIT

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null
cd "$ROOT"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
xcodebuild build-for-testing \
  -project AirDesk.xcodeproj \
  -scheme AirDesk \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO >"$LOG_DIR/build.log" 2>&1

xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.webrtcprobe enabled -bool YES
xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.webrtcprobe samples -int "$SAMPLES"

for payload in "${PAYLOADS[@]}"; do
  xcrun simctl spawn "$SIMULATOR_ID" defaults write com.airdesk.webrtcprobe payloadBytes -int "$payload"
  set +e
  xcodebuild test-without-building \
    -project AirDesk.xcodeproj \
    -scheme AirDesk \
    -destination "$DESTINATION" \
    -only-testing:AirDeskTests/WebRTCLoopbackProbeTests \
    CODE_SIGNING_ALLOWED=NO >"$LOG_DIR/test-$payload.log" 2>&1
  status=$?
  set -e
  raw="$(sed -n 's/^AIRDESK_WEBRTC_RESULT //p' "$LOG_DIR/test-$payload.log" | tail -n 1)"
  if [[ -z "$raw" ]]; then
    echo "No probe result for ${payload} B (status $status)." >&2
    tail -n 40 "$LOG_DIR/test-$payload.log" >&2
    exit 1
  fi
  printf '%s\n' "$raw" >"$OUT_DIR/${payload}b.json"
  echo "$OUT_DIR/${payload}b.json"
done

echo "run: $OUT_DIR"

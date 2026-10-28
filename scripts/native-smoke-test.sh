#!/usr/bin/env bash
set -euo pipefail

UDID="${1:-${SIM_UDID:-3B46FDF8-1482-4517-99F3-D6EF46A85133}}"
BUNDLE_ID="${BUNDLE_ID:-com.airdesk.ios}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/airdesk}"
APP="${APP:-$PROJECT_DIR/DerivedData/Build/Products/Debug-iphonesimulator/AirDesk.app}"
DEVICE_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data"
JSON_NAME="airdesk-native-smoke.json"
LAUNCH_LOG="${TMPDIR:-/tmp}/airdesk-native-smoke-launch.log"

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  echo "Build it first with xcodebuild." >&2
  exit 1
fi

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
timeout 120 xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

find "$DEVICE_DIR/Containers/Data/Application" -name "$JSON_NAME" -delete 2>/dev/null || true
nohup xcrun simctl launch "$UDID" "$BUNDLE_ID" -AirDeskSmokeTest >"$LAUNCH_LOG" 2>&1 &

for _ in $(seq 1 180); do
  RESULT=$(find "$DEVICE_DIR/Containers/Data/Application" -name "$JSON_NAME" -print -quit 2>/dev/null || true)
  if [[ -n "$RESULT" ]]; then
    cat "$RESULT"
    echo
    if grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' "$RESULT"; then
      exit 0
    fi
    exit 1
  fi
  sleep 1
done

echo "Timed out waiting for $JSON_NAME" >&2
cat "$LAUNCH_LOG" >&2 || true
ls -t "$HOME/Library/Logs/DiagnosticReports"/AirDesk-*.ips 2>/dev/null | head -3 >&2 || true
exit 1

#!/bin/bash
set -euo pipefail

DEVICE="${1:-iPhone 16 Pro}"
BUNDLE="${2:-com.airdesk.ios}"
APP="${3:-$HOME/airdesk/DerivedData/Build/Products/Debug-iphonesimulator/AirDesk.app}"
if [ "$#" -gt 3 ]; then
  shift 3
else
  shift "$#"
fi

UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -n 1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
if [ -z "$UDID" ]; then
  echo "No available simulator named $DEVICE" >&2
  exit 1
fi

if ! xcrun simctl list devices | grep -F "$UDID" | grep -q "(Booted)"; then
  nohup xcrun simctl boot "$UDID" >/tmp/airdesk-sim-boot.log 2>&1 &
fi

perl -e 'alarm shift; exec @ARGV' 120 xcrun simctl bootstatus "$UDID" -b >/tmp/airdesk-sim-bootstatus.log 2>&1 || true
xcrun simctl install "$UDID" "$APP"
nohup xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/tmp/airdesk-sim-launch.log 2>&1 &
echo "UDID: $UDID"
echo "Launch log: /tmp/airdesk-sim-launch.log"

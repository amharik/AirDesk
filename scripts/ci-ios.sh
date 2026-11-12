#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${AIRDESK_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro,OS=latest}"

cd "$ROOT"

if [[ ! -d core/airdesk-ffi/apple/Artifacts/airdesk_ffiFFI.xcframework ]]; then
    ./scripts/build-core-apple.sh
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required. Install it with: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project AirDesk.xcodeproj >/dev/null

xcodebuild build-for-testing \
    -project AirDesk.xcodeproj \
    -scheme AirDesk \
    -destination "$DESTINATION" \
    CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building \
    -project AirDesk.xcodeproj \
    -scheme AirDesk \
    -destination "$DESTINATION" \
    -only-testing:AirDeskTests \
    CODE_SIGNING_ALLOWED=NO

xcodebuild build-for-testing \
    -project AirDesk.xcodeproj \
    -scheme AirDeskUITests \
    -destination "$DESTINATION" \
    CODE_SIGNING_ALLOWED=NO

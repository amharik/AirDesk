#!/usr/bin/env bash
set -euo pipefail

REMOTE="${REMOTE:-ubuntu@sillyoci}"
REMOTE_DIR="${REMOTE_DIR:-airdesk-android-agent}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() {
    printf '[airdesk-build] %s\n' "$*"
}

if [ ! -d "$REPO_ROOT/android" ]; then
    log "android project not found under $REPO_ROOT"
    exit 1
fi

log "Syncing $REPO_ROOT to $REMOTE:~/$REMOTE_DIR"
rsync -az --delete \
    --exclude '.git/' \
    --exclude 'android/.gradle/' \
    --exclude 'android/build/' \
    --exclude 'android/build-artifacts/' \
    --exclude 'android/app/build/' \
    "$REPO_ROOT/" "$REMOTE:$REMOTE_DIR/"

if ! ssh "$REMOTE" "test -x \"\$HOME/android-sdk/build-tools/35.0.0/aapt2\""; then
    log "Android toolchain missing on $REMOTE; installing it"
    ssh "$REMOTE" 'bash -s' < "$SCRIPT_DIR/install-toolchain.sh"
fi

log "Building and testing on $REMOTE"
ssh "$REMOTE" "REMOTE_DIR='$REMOTE_DIR' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
cd "$HOME/$REMOTE_DIR/android"
./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest
REMOTE_SCRIPT

mkdir -p "$REPO_ROOT/android/build-artifacts"
rsync -az \
    "$REMOTE:$REMOTE_DIR/android/app/build/outputs/apk/debug/app-debug.apk" \
    "$REPO_ROOT/android/build-artifacts/AirDesk-debug.apk"
log "APK: $REPO_ROOT/android/build-artifacts/AirDesk-debug.apk"

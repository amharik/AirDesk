#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
GENERATED="$CORE/airdesk-ffi/generated"

export PATH="${HOME}/.cargo/bin:${PATH}"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/home/ubuntu/android-sdk}}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$(find "$ANDROID_HOME/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)}}"

if ! command -v cargo-ndk >/dev/null 2>&1; then
    echo "cargo-ndk is required. Install it with: cargo install cargo-ndk" >&2
    exit 1
fi

rm -rf "$GENERATED/kotlin" "$GENERATED/jniLibs"
mkdir -p "$GENERATED/kotlin" "$GENERATED/jniLibs"

cargo build --manifest-path "$CORE/Cargo.toml" -p airdesk-ffi --lib
HOST_LIB="$(find "$CORE/target/debug/deps" -maxdepth 1 -name 'libairdesk_ffi.so' | head -1)"
if [[ -z "$HOST_LIB" ]]; then
    echo "Unable to locate the host uniffi library." >&2
    exit 1
fi

(
    cd "$CORE"
    cargo run --quiet -p airdesk-ffi --bin uniffi-bindgen -- \
        generate --library "$HOST_LIB" --language kotlin --out-dir "$GENERATED/kotlin"
)

(
    cd "$CORE"
    cargo ndk \
        --target arm64-v8a \
        --target x86_64 \
        --output-dir "$GENERATED/jniLibs" \
        build -p airdesk-ffi --lib --release
)

echo "Generated Kotlin bindings in $GENERATED/kotlin"
echo "Built Android libraries in $GENERATED/jniLibs"

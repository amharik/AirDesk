#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
DIST="$CORE/airdesk-wasm/dist"
WASM="$CORE/target/wasm32-unknown-unknown/release/airdesk_wasm.wasm"

export PATH="${HOME}/.cargo/bin:${PATH}"
export CARGO_INCREMENTAL=0
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

if ! rustup target list --installed | grep -qx wasm32-unknown-unknown; then
    echo "Missing Rust target wasm32-unknown-unknown. Run: rustup target add wasm32-unknown-unknown" >&2
    exit 1
fi

if ! command -v wasm-bindgen >/dev/null 2>&1; then
    echo "wasm-bindgen is required. Install the CLI version matching core/Cargo.lock." >&2
    exit 1
fi

build() {
    local output="$1"
    cargo build --manifest-path "$CORE/Cargo.toml" -p airdesk-wasm --lib --release --target wasm32-unknown-unknown
    wasm-bindgen --target web --out-name airdesk_wasm --out-dir "$output" "$WASM"
}

rm -rf "$DIST" "$DIST.verify"
build "$DIST"

if [[ "${AIRDESK_CORE_WASM_VERIFY_DETERMINISM:-0}" == "1" ]]; then
    build "$DIST.verify"
    diff -ru "$DIST" "$DIST.verify"
    rm -rf "$DIST.verify"
fi

(
    cd "$DIST"
    find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

echo "Built $DIST"

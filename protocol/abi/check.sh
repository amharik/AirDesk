#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ABI_DIR="$ROOT/protocol/abi"
WIT_DIR="$ABI_DIR/wit"
MAIN="$WIT_DIR/airdesk-host-abi.wit"
WASI_IO="$WIT_DIR/deps/io/streams.wit"
WIT_03="$WIT_DIR/airdesk-host-abi-0_3.wit"
FIXTURE="$ROOT/protocol/fixtures/host-abi/wit-v1.json"
WASM_TOOLS=${WASM_TOOLS:-wasm-tools}
EXPECTED_WASM_TOOLS=1.263.0

fail() {
  echo "host ABI check failed: $*" >&2
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "missing $1"
}

require_text() {
  grep -F -- "$2" "$1" >/dev/null || fail "missing '$2' in ${1#"$ROOT/"}"
}

reject_text() {
  if grep -F -- "$2" "$1" >/dev/null; then
    fail "unexpected '$2' in ${1#"$ROOT/"}"
  fi
}

require_file "$MAIN"
require_file "$WASI_IO"
require_file "$FIXTURE"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Comment-free copies are used for security-sensitive token checks.
sed 's://.*::' "$MAIN" > "$TMP/main.wit"

require_text "$MAIN" 'package airdesk:host-abi@0.2.0;'
require_text "$MAIN" 'world capability-host {'
require_text "$MAIN" 'import wasi:io/streams@0.2.0;'
require_text "$WASI_IO" 'package wasi:io@0.2.0;'

for interface in types vfs-service pty-service display-sink; do
  require_text "$MAIN" "interface $interface {"
done

for declaration in \
  'mount-capability: func' \
  'stat: func' \
  'open-at: func' \
  'read-stream: func' \
  'write-stream: func' \
  'readdir: func' \
  'spawn: func' \
  'stdin: func' \
  'stdout: func' \
  'resize: func' \
  'terminate: func' \
  'wait: func' \
  'credits: func' \
  'register-sink: func' \
  'state: func' \
  'update-presentation: func'
do
  require_text "$MAIN" "$declaration"
done

for code in \
  invalid-argument unsupported lease-invalid lease-expired lease-revoked \
  permission-denied not-found path-escape busy unavailable flow-control conflict internal
do
  require_text "$MAIN" "    $code,"
done

require_text "$MAIN" 'record capability-grant {'
require_text "$MAIN" 'token: capability-token,'
require_text "$MAIN" 'context: lease-context,'
require_text "$MAIN" 'record pty-credit-window {'
require_text "$MAIN" 'max-in-flight-bytes: u64,'
require_text "$MAIN" 'resume-threshold-bytes: u64,'
require_text "$MAIN" 'max-chunk-bytes: u64,'

# The 0.2 world must not use component-model async streams, and the capability
# host ABI must have no presentation-frame submission path.
if grep -Eq 'stream<|future<' "$TMP/main.wit"; then
  fail "0.2 world contains 0.3 stream<T>/future<T> types"
fi
if grep -Eqi 'submit|frame|surface|pixel' "$TMP/main.wit"; then
  fail "display frame submission or surface payload found in host ABI"
fi

# Frozen contract fixture.
require_text "$FIXTURE" '"package": "airdesk:host-abi@0.2.0"'
require_text "$FIXTURE" '"world": "capability-host"'
require_text "$FIXTURE" '"witPath": "protocol/abi/wit/airdesk-host-abi.wit"'
require_text "$FIXTURE" '"revalidate": "every-host-call"'
require_text "$FIXTURE" '"streamHandlesInheritGrant": true'
require_text "$FIXTURE" '"maxInFlightBytes": 262144'
require_text "$FIXTURE" '"resumeThresholdBytes": 131072'
require_text "$FIXTURE" '"maxChunkBytes": 65536'
require_text "$FIXTURE" '"frameSubmission": false'
require_text "$FIXTURE" '"inputSubscription": false'
require_text "$FIXTURE" '"wasi03World": "separate-world"'
require_text "$FIXTURE" '"mixedWorlds": "rejected"'
for interface in vfs-service pty-service display-sink; do
  require_text "$FIXTURE" "\"$interface\": {"
done
for code in lease-invalid lease-expired lease-revoked path-escape flow-control; do
  require_text "$FIXTURE" "\"$code\""
done

# A 0.3 world, when P2-11 adds it, must be a separate 0.3 package using
# stream<T>/future<T>, with no 0.2 package reference and no wasi:io import.
if [ -f "$WIT_03" ]; then
  sed 's://.*::' "$WIT_03" > "$TMP/main03.wit"
  require_text "$WIT_03" 'package airdesk:host-abi@0.3.0;'
  require_text "$WIT_03" 'world capability-host-0-3 {'
  if ! grep -Eq 'stream<|future<' "$TMP/main03.wit"; then
    fail "0.3 world does not use stream<T>/future<T>"
  fi
  require_text "$WIT_03" 'async func'
  for declaration in \
    'read-via-stream:' \
    'write-via-stream:' \
    'read-stdout:' \
    'write-stdin:' \
    'mount-capability:' \
    'spawn:' \
    'register-sink:'
  do
    require_text "$WIT_03" "$declaration"
  done
  if grep -Eqi 'submit|frame|surface|pixel' "$TMP/main03.wit"; then
    fail "display frame submission or surface payload found in 0.3 host ABI"
  fi
  reject_text "$TMP/main03.wit" 'wasi:io'
  reject_text "$TMP/main03.wit" 'airdesk:host-abi@0.2.0'
  reject_text "$TMP/main03.wit" 'capability-host {'
  reject_text "$TMP/main.wit" 'airdesk:host-abi@0.3.0'
else
  reject_text "$TMP/main.wit" 'airdesk:host-abi@0.3.0'
fi

# Structural checks are not a substitute for parsing the package.
if ! command -v "$WASM_TOOLS" >/dev/null 2>&1; then
  fail "wasm-tools $EXPECTED_WASM_TOOLS required (set WASM_TOOLS=/path/to/wasm-tools)"
fi
ACTUAL_WASM_TOOLS=$("$WASM_TOOLS" --version | awk '{print $2}')
if [ "$ACTUAL_WASM_TOOLS" != "$EXPECTED_WASM_TOOLS" ]; then
  fail "wasm-tools $EXPECTED_WASM_TOOLS required, found $ACTUAL_WASM_TOOLS"
fi

# Resolve 0.2 from an isolated package directory so a future 0.3 sibling cannot
# be merged into the 0.2 world by the resolver.
mkdir -p "$TMP/wit02"
cp "$MAIN" "$TMP/wit02/"
cp -R "$WIT_DIR/deps" "$TMP/wit02/deps"
"$WASM_TOOLS" component wit "$TMP/wit02" >/dev/null || fail "0.2 WIT package did not resolve"
if [ -f "$WIT_03" ]; then
  "$WASM_TOOLS" component wit "$WIT_03" >/dev/null || fail "0.3 WIT did not resolve"
fi

echo "Host ABI 0.2 WIT, lease contract, credits and fixture are current."

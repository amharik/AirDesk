#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
PACKAGE="$CORE/airdesk-ffi/apple"
ARTIFACTS="$PACKAGE/Artifacts"
BUILD="$PACKAGE/.build"
TARGETS="aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios"

export PATH="${HOME}/.cargo/bin:${PATH}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "build-core-apple.sh requires macOS with Xcode." >&2
    exit 1
fi

for target in $TARGETS; do
    if ! rustup target list --installed | grep -qx "$target"; then
        echo "Missing Rust target $target. Run: rustup target add $target" >&2
        exit 1
    fi
done

rm -rf "$BUILD" "$ARTIFACTS"
mkdir -p "$BUILD/bindgen" "$BUILD/headers" "$ARTIFACTS"

cargo build --manifest-path "$CORE/Cargo.toml" -p airdesk-ffi --lib
HOST_LIB="$(find "$CORE/target/debug/deps" -maxdepth 1 -name 'libairdesk_ffi.dylib' | head -1)"
if [[ -z "$HOST_LIB" ]]; then
    echo "Unable to locate the host uniffi library." >&2
    exit 1
fi

(
    cd "$CORE"
    cargo run --quiet -p airdesk-ffi --bin uniffi-bindgen -- \
        generate --library "$HOST_LIB" --language swift --out-dir "$BUILD/bindgen"
)

cp "$BUILD/bindgen/airdesk_ffi.swift" "$PACKAGE/Sources/AirDeskCore/AirDeskCore.swift"
cp "$BUILD/bindgen/airdesk_ffiFFI.h" "$BUILD/headers/airdesk_ffiFFI.h"

for target in $TARGETS; do
    cargo build --manifest-path "$CORE/Cargo.toml" -p airdesk-ffi --lib --release --target "$target"
done

lipo -create \
    "$CORE/target/aarch64-apple-ios-sim/release/libairdesk_ffi.a" \
    "$CORE/target/x86_64-apple-ios/release/libairdesk_ffi.a" \
    -output "$BUILD/libairdesk_ffi-sim.a"

make_framework() {
    local library="$1"
    local platform="$2"
    local output="$3"

    mkdir -p "$output/Headers" "$output/Modules"
    cp "$library" "$output/airdesk_ffiFFI"
    cp "$BUILD/headers/airdesk_ffiFFI.h" "$output/Headers/airdesk_ffiFFI.h"
    cat > "$output/Modules/module.modulemap" <<'MODULEMAP'
framework module airdesk_ffiFFI {
    header "airdesk_ffiFFI.h"
    export *
}
MODULEMAP
    cat > "$output/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>airdesk_ffiFFI</string>
    <key>CFBundleIdentifier</key>
    <string>com.airdesk.core.ffi</string>
    <key>CFBundleName</key>
    <string>airdesk_ffiFFI</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>${platform}</string></array>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
</dict>
</plist>
PLIST
}

make_framework "$CORE/target/aarch64-apple-ios/release/libairdesk_ffi.a" "iPhoneOS" "$BUILD/ios/airdesk_ffiFFI.framework"
make_framework "$BUILD/libairdesk_ffi-sim.a" "iPhoneSimulator" "$BUILD/iossim/airdesk_ffiFFI.framework"

xcodebuild -create-xcframework \
    -framework "$BUILD/ios/airdesk_ffiFFI.framework" \
    -framework "$BUILD/iossim/airdesk_ffiFFI.framework" \
    -output "$ARTIFACTS/airdesk_ffiFFI.xcframework" >/dev/null

echo "Built $ARTIFACTS/airdesk_ffiFFI.xcframework"

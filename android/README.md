# AirDesk Android device-agent baseline

Independent Android Gradle project for on-device testing. It builds against the
Android SDK, not the host Mac/Xcode project.

## Toolchain

- JDK: OpenJDK 17.0.20.1 (`17.0.20.1+1-1-22.04-Ubuntu`)
- Android SDK: platform-tools 37.0.1, `platforms;android-35` (rev 2), `build-tools;35.0.0`
- Gradle: 8.9 (wrapper)
- Android Gradle Plugin: 8.7.3
- Kotlin: 2.0.21
- Compose BOM: 2024.12.01
- Build host used: `ubuntu@sillyoci`, Ubuntu 22.04 aarch64

On aarch64 the SDK `aapt2` is an x86-64 binary. The install script enables
`qemu-user-static` plus amd64 glibc when needed so the normal Gradle build works.

## Toolchain install

```bash
android/scripts/install-toolchain.sh
```

Installs OpenJDK 17 if required, accepts Android SDK licenses, and installs
`platform-tools`, `platforms;android-35`, and `build-tools;35.0.0` under
`$HOME/android-sdk` (override with `ANDROID_SDK_ROOT`).

## Remote build

```bash
android/scripts/build-on-sillyoci.sh
```

The script rsyncs the repo to `~/airdesk-android-agent`, installs the toolchain
if missing, and runs:

```bash
./gradlew :app:assembleDebug :app:testDebugUnitTest
```

It copies the APK back to `android/build-artifacts/AirDesk-debug.apk`.

## Implemented

- `com.airdesk.android`, minSdk 26, compile/targetSdk 35, Compose Material 3 UI.
- Persistent P-256 Android Keystore identity, alias `airdesk.device.p256`.
- Device ID `ad-device:` + lowercase hex SHA-256 of the X.509 SPKI.
- Editable display name and local peer registry in SharedPreferences.
- Local pairing-offer JSON (`adfp` / `0.1` / `pairing-offer`) with a 5-minute expiry.
- Strict offer parsing, P-256/device-ID matching, expiry and replay checks.
- Capability descriptors for display, pointer, keyboard, camera, files/read and health.
- Availability and authorization kept as separate axes; pairing grants nothing.
- Real `CAMERA` permission request and hardware/permission reflection.
- Diagnostics showing identity, key details, public key, capability counts and build data.
- Presentation WebView through `WebViewAssetLoader` at
  `https://appassets.androidplatform.net/assets/DesktopShell/` with JavaScript and
  DOM storage enabled, file access disabled, and non-local navigation blocked.
- JVM unit tests for device ID formatting, pairing validation/replay, offer creation,
  registry revocation, and capability availability/authorization separation.

## Deferred / not claimed

- AD-PAIR-1, RFC 9383 SPAKE2+, PIN/QR exchange, channel binding, signatures and session keys.
- Capability grants, leases, COSE tokens and remote capability invocation.
- LAN/network transport, discovery, and display/input/file/camera streaming.
- Device-wide filesystem access.
- Remote revocation propagation. Local peer revocation only.

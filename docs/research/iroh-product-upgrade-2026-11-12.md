# Iroh product upgrade spike — 2026-11-12

## Question

P1-09 asks whether AirDesk can move the product Iroh pins to `1.4.x`, what API
gaps remain, and whether path migration/relay diagnostics are available before
changing the product dependency.

## Method

Availability was checked on 2026-11-12 against the official release and package
registries, then against a fresh `iroh-ffi` `v1.2.0` checkout.

```sh
git ls-remote --tags https://github.com/n0-computer/iroh-ffi.git
git -C /tmp/opencode/iroh-ffi rev-parse --short HEAD
rg -n "func (paths|watchPaths|watchPathEvents|watchNetworkChange|watchHomeRelay)" \
  /tmp/opencode/iroh-ffi/iroh-ffi/src
rg -n "PathSnapshot|PathEvent|PathStats" /tmp/opencode/iroh-ffi/iroh-ffi/src
rg -n "watchPaths|watchPathEvents|PathSnapshot|watchNetworkChange|watchHomeRelay" \
  AirDesk android/app/src -g '*.{swift,kt}'
```

Registry checks queried the Maven Central metadata for
`computer.iroh:iroh-android` and the GitHub releases/tags for `n0-computer/iroh-ffi`.

## Results

### Availability

- The newest `iroh-ffi` release and tag is `v1.2.0`, published `2026-10-22`
  (`66a8d61`). No `1.3.x` or `1.4.x` FFI tag exists.
- Maven Central's latest `computer.iroh:iroh-android` artifact is `1.2.0`.
- The Rust crate `iroh` is separately published at `1.4.1` and is used only by
  `research/iroh-probe/Cargo.toml`.
- The product pins therefore remain `IrohLib` `1.2.0` in `project.yml` and
  `iroh-android` `1.2.0` in `android/app/build.gradle.kts`.

Do not upgrade the Swift or Android product dependency until matching FFI and
Maven releases exist, or until a separately built and qualified binding is
approved. The Rust probe is not a product substitute.

### API gaps

`iroh-ffi` `1.2.0` already exposes path and network diagnostics:

- `paths() -> [PathSnapshot]`
- `watchPathEvents(callback:) -> WatchHandle`
- `watchPaths(callback:) -> WatchHandle`
- `watchHomeRelay(callback:) -> WatchHandle`
- `watchNetworkChange(callback:) -> WatchHandle`

`PathSnapshot` carries the path id, selected state, remote address, direct-IP
and relay flags, RTT and path statistics. AirDesk's current `IrohFabricPath`
already maps the selected path, direct/relay flags and RTT from `paths()`.

The current product surface does not subscribe to `watchPathEvents`,
`watchPaths`, `watchNetworkChange` or `watchHomeRelay`. It also does not expose
a path-migration callback to the session UI. Those APIs are available at the
current pin; a product pin change is not required to consume them.

### Loopback diagnostics

`AirDeskTests/IrohFabricTransportTests.testDirectLoopbackReliableAndMovement`
runs direct-only loopback endpoints and verifies selected-path diagnostics,
reliable control/runtime/sync frames and movement datagrams. `IrohFabricPeer`
refreshes `paths` on a timer and publishes the selected path for diagnostics.

This is loopback evidence only. It does not establish Wi-Fi-to-cellular roaming,
relay fallback behavior, NAT rebinding or physical-device path migration. Those
remain live-network/hardware gates.

### UI relevance

P4-04 can consume the existing selected path, relay flag and RTT from
`IrohFabricPeer.paths` without changing the Iroh pin. It must label the status
as current-path diagnostics, not claim automatic roaming or multipath support.

### Self-built 1.4.1 binding evidence

Because no FFI release exists, `iroh-ffi` `v1.2.0` (`66a8d61`) was patched to
the exact Rust pins below and built locally. `research/iroh-ffi-1.4.patch`
records the dependency and macOS-fat-slice changes.

```toml
iroh = "=1.4.1"
iroh-base = "=1.4.1"
iroh-metrics = "=1.0.2"
iroh-relay = "=1.4.1"
iroh-services = "=2.0.0"
iroh-tickets = "=1.0.0"
n0-error = "=1.0.3"
```

The Swift and Kotlin targets both generated. On macOS, `cargo check` passed and
`cargo test --lib` passed 26/26. The xcframework contained iOS arm64, iOS
simulator arm64+x86_64, Mac Catalyst arm64 and macOS arm64 slices. SHA-256:

- iOS arm64: `c97177722ea4e2002cc2392b090871a1fdac781a7dafea8f902445593c96cdec`
- iOS simulator: `3bfc632c07bc2a3cc6a5496649d88efafeda3c40e49eeeab8f385d3fe1fd6c7a`
- Mac Catalyst: `c24b3de1ed9b757ff46730ffab2953898d435c00065c5b499bf497ae23383790`
- macOS arm64: `fabbd0a89a5604ae8e8ef01e42e4bf44ab3664d74e324965de0118f9cb4efa5e`
- Swift bindings: `63fbfbc1a1761165d192682ca0aff360abdfcad805449017a0c7f508754993ca`
- Kotlin bindings: `043ddfd83509b1f5c78461652137a4b1ab0e3ceadddef7cbe16c2ca67a2a5591`

On Linux aarch64 (`sillyoci`), using Rust 1.98.1, `cargo-ndk` 3.5.4 and the
aarch64 NDK r29 repack, the Android arm64 target built. The AAR was published
locally as `computer.iroh:iroh-android:1.4.1` and contained
`jni/arm64-v8a/libiroh_ffi.so` (12,904,424 bytes, 16 KB LOAD alignment).

- `libiroh_ffi.so`: `ba22cc144f6c768eb3e7645d1d88fdd917c2338970f12d3ebfcad6d38e37322d`
- AAR: `2698e4f91a85cc715941e6cfc16bb82fac35ab61faac1053ed149bcd6fafc163`
- debug APK: `d2cb1166b424b5fc0a96a6822f7f87c63a79f0d15eecdf749f1ae13edbaa279e`

Qualification runs:

- iOS: temporarily pointed `project.yml` at the local package, then full
  `xcodebuild test` passed 578 tests, 1 skipped, 0 failures. The dedicated
  `IrohFabricPeerTests` and `IrohFabricTransportTests` passed including direct
  loopback transport.
- Android: temporarily pointed the app at the local `1.4.1` AAR, then
  `testDebugUnitTest lintDebug assembleDebug` passed 171 tests, 0 failures. The
  APK packaged `lib/arm64-v8a/libiroh_ffi.so`.

Limitations and rollback:

- Android has only the `arm64-v8a` native slice; emulator ABIs and other device
  ABIs are not built. The macOS xcframework has no macOS x86_64 slice, so a
  standalone `swift test` on an Intel host fails to link `RustBuffer`; the iOS
  simulator suite is the exercised Swift gate.
- No relay transition, Wi-Fi/cellular roaming, NAT rebinding, physical-device
  Iroh run or product rollback drill was performed.
- Rollback is to restore `project.yml` from
  `/tmp/opencode/airdesk-project.yml.bak`, remove the local `mavenLocal`
  `1.4.1` artifacts, revert the temporary `1.4.1` app dependency to `1.2.0`,
  and regenerate the Xcode project. The Mac checkout was restored after the iOS
  run; only untracked DerivedData/Dist/screenshot directories remained.
- The built artifacts are temporary qualification inputs. No product pin or
  tracked source dependency was changed.

## Decision

- Keep the `IrohLib` and `iroh-android` `1.2.0` product pins.
- Treat the self-built `1.4.1` bindings as code-level evidence, not a product
  release. Do not claim Iroh `1.4.x` product availability or roaming support.
- Unblock P4-04's continuity pill using the existing `1.2.0` path diagnostics.
- Keep live path migration, relay transition and roaming as an explicit
  hardware/live-network gate for P1-09/P1-10.

## Follow-up gates

1. Publish and qualify matching `iroh-ffi` and `iroh-android` releases before any
   product pin change.
2. Add a loopback/harness test for a path-event transition once a controllable
   migration fixture exists.
3. Exercise direct-to-relay and relay-to-direct transitions on real Wi-Fi,
   cellular and tailnet paths before claiming automatic roaming.
4. Keep diagnostics truthful: selected path and RTT are current observations,
   not a guarantee of future migration.

## Qualification decision (2026-11-12)

User direction allows a self-built Iroh 1.4 FFI path only when the existing
Swift/Kotlin language targets are present. That path still needs the normal
loopback, relay, roaming, rollback and physical/live-network evidence before a
product pin changes. Until then the `1.2.0` pins are the qualified product
baseline and no `1.4.x` availability or roaming claim is permitted.

## Live tailnet and relay probe (2026-11-13)

The Rust `iroh` 1.4.1 probe was run from the macOS host to `sillyoci` over the
tailnet, with five samples per payload. Evidence is under
`docs/research/runs/2026-11-13T095647Z-iroh-tailnet-baseline` and
`docs/research/runs/2026-11-13T100030Z-iroh-relay-fallback`.

| Path | Payload | Delivered | Selected path | Relay addresses | p50 control RTT | Reconnect |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| Tailnet direct | 64 B | 5/5 | direct | 0 | 34.69 ms | 77.26 ms |
| Tailnet direct | 1 KiB | 5/5 | direct | 0 | 34.55 ms | 70.52 ms |
| Tailnet direct | 16 KiB | 5/5 | direct | 0 | 56.72 ms | 236.57 ms |
| Public relay | 64 B | 5/5 | relay | 1 | 119.08 ms | 347.42 ms |
| Public relay | 1 KiB | 5/5 | relay | 1 | 188.08 ms | 438.82 ms |
| Public relay | 16 KiB | 5/5 | relay | 1 | 570.69 ms | 1269.19 ms |

All runs reported the expected direct or relay path, no failures, and a
reconnect measurement. This qualifies the current probe over a real tailnet and
the public relay. It does not qualify Wi-Fi-to-cellular roaming, NAT rebinding,
physical iPhone/Android path migration, or a product `iroh-ffi` pin change.
Those remain P1-09/P5-06/P5-07/P5-08 gates.

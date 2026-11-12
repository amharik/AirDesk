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

## Decision

- Keep the `IrohLib` and `iroh-android` `1.2.0` product pins.
- Do not claim Iroh `1.4.x` product availability or roaming support.
- Unblock P4-04's continuity pill using the `1.2.0` path diagnostics that
  already exist.
- Keep live path migration and relay roaming as an explicit hardware/live-
  network gate for P1-09/P1-10.

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

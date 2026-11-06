# ADR-021: Iroh native transport adoption

- **Status:** Accepted — native data-plane implementation in progress
- **Date:** 2026-11-06
- **Deciders:** Engineering lead, transport owner
- **Scope:** Native peer transport, relay policy, browser path, identity storage, Swift SDK integration
- **Supersedes:** None
- **Amends:** ADR-013 native transport sequencing; ADR-003 dependency admission for `iroh-ffi`
- **Related:** ADR-001, ADR-003, ADR-004, ADR-008, ADR-010, ADR-011, ADR-012, ADR-013, ADR-014

## Context

User direction on 2026-11-06 adopts Iroh for the native peer data plane. The Rust T4 probe established loopback and two-host Iroh/QUIC operation, including a forced relay-only run. Iroh now publishes an official Swift SDK, `iroh-ffi` `v1.2.0`, with an `IrohLib` module and a prebuilt XCFramework.

The product still needs a browser endpoint, and the existing WebSocket path remains the browser baseline. Relay behavior is the main architectural risk: Iroh normally uses a home relay for coordination and fallback, while AirDesk requires an explicit, authorized relay policy rather than a hidden public dependency.

## Decision

### 1. Native data plane

Use Iroh as the native peer data plane for direct device-to-device transport. ADFP semantics remain transport-neutral and do not depend on Iroh types.

### 2. Swift SDK

Use the official `IrohLib` package from `https://github.com/n0-computer/iroh-ffi`, pinned to `1.2.0`, with iOS 17.5 as the minimum deployment target. Do not vendor a separately built Rust XCFramework unless the official package fails a qualification gate.

### 3. Identity

Store the endpoint secret key in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The endpoint identity is transport identity, not user identity, workspace ownership or a capability grant. Pairing and authorization remain governed by ADR-011 and ADR-012.

### 4. Pairing and addressing

Use the Iroh endpoint ticket as the reachability payload for pairing. A ticket is not a trust credential. A peer must still complete AirDesk pairing and capability authorization before control or data traffic is accepted.

### 5. Relay policy

The default development and test policy is `directOnly` using `presetMinimal()` with `RelayMode.disabled()`.

Production relay support must be explicit and self-hosted:

- relay URLs must be provided as HTTPS URLs;
- the public n0 relay must not be a product default;
- an empty or malformed relay configuration fails closed;
- the selected path and its direct/relay state must be visible in diagnostics;
- no public relay or hidden discovery service may be enabled implicitly.

### 6. Wire mapping

- ALPN: `airdesk/fabric/1`.
- Reliable ADFP channels (control, input edges, runtime, resource, display) use one bidirectional stream per frame with a 1-byte channel identifier, a 4-byte big-endian payload length and the payload. The reliable payload limit is 1 MiB.
- Movement uses an unreliable datagram containing exactly the 16-byte `PackedPointerFrame`; movement is never sent on a reliable stream.
- Channel semantics remain those in `docs/protocols/transport-mapping.md`.

### 7. Browser path

The browser endpoint continues to use WebSocket under ADR-014. This ADR does not add Iroh to the browser. WebTransport and WebRTC qualification remain separate gates.

## Consequences

- iOS 17.5 becomes the minimum deployment target for the app.
- The app links `IrohLib`, `SystemConfiguration`, `CoreWLAN` and `Network`.
- Direct-only mode works without relays but can fail when no direct address is reachable.
- Self-hosted relay operation and automatic direct-to-relay behavior still require labeled network evidence.
- Physical-device, direct-underlay and self-hosted-relay qualification remain open.
- The R6 decision still decides the broader fabric architecture, but it no longer gates implementation of the Iroh transport adapter.

## Validation

The initial integration is accepted when:

1. the app builds and unit tests pass on the Mac iOS simulator;
2. a loopback test exchanges reliable control/runtime frames and movement datagrams;
3. malformed channels, oversized frames, invalid movement payloads and invalid relay URLs fail closed;
4. diagnostics expose endpoint identity, ticket, path state and relay policy;
5. the second-device harness and existing SSH paths remain unaffected.

Initial loopback validation passed on 2026-11-06 with Xcode 16.4 on the Intel Mac mini:

- `xcodebuild build-for-testing` succeeded for iPhone 16 Pro iOS 18.6 simulator with `ENABLE_ON_DEMAND_RESOURCES=NO`;
- `IrohFabricTransportTests` passed 3/3 in 0.7 s, covering frame validation, fail-closed relay policy, reliable control/runtime frames, movement datagrams, tickets and diagnostics;
- the full `AirDeskTests` suite ran 247 tests with 244 passes, 1 skip and 2 failures; both failures were `DesktopShellIntegrationTests` under full-suite simulator load, and both passed when rerun in isolation.

App wiring remains `XPORT-05`; the browser path and production release sequencing remain unchanged.

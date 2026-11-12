# AirDesk 100x/1000x Masterplan — Execution Breakdown

- **Status:** Planning only — no implementation commitment and no ADR promotion
- **Date:** 2026-11-11
- **Baseline:** `dev` at `4a12420`, plus the verified P5-03 iOS client decode/frame pacing path
- **Input:** User-supplied 100x product / 1000x UX masterplan
- **Related:** `milestones.md`, `docs/planning/workspace-fabric-plan.md`, `docs/planning/release-roadmap.md`, ADR-001 through ADR-026

This document maps the masterplan onto the repository as it actually exists. It is deliberately more conservative than the source plan: the 100x/1000x targets are treated as hypotheses, the Rust core is staged behind a compatibility boundary rather than rewritten in one pass, and hardware/live-network claims remain gated.

## 1. Executive recommendation

Do not execute the masterplan as a four-week big-bang Rust rewrite. Execute it as six parallel workstreams with a hard compatibility boundary:

1. Keep the landed Phase 0 and P1 protocol work green, then close remote runtime and placement gaps.
2. Close the trust/protocol/remote-execution gaps in Swift, Kotlin, TypeScript and Rust using shared fixtures.
3. Make the native agent contract and WIT ABI authoritative before adding more platform-specific capability code.
4. Extract low-risk codecs and state machines into `libairdesk-core` first; move cryptography only after cross-language equivalence is proven.
5. Upgrade UX/input/terminal in feature-flagged slices.
6. Treat native display streaming, persistent PTY, Cast and transport qualification as hardware/live-network-gated work.

The source plan's 16-week schedule is not credible at current staffing. The task inventory below is roughly **75–110 engineer-weeks**. With four to five full-time engineers working disjoint lanes, the code-level path is about **20–28 calendar weeks**, before physical-device and network qualification.

## 2. Baseline audit

### 2.1 Verified current state

- Release baseline exists: `debug-2026-11-09-4` with Android APK, unsigned iOS device IPA and simulator zip published by `.github/workflows/debug-release.yml`.
- Current tracked inventory:
  - `AirDesk/`: 123 Swift app files.
  - `AirDeskTests/`: 65 Swift unit-test files.
  - `AirDeskUITests/`: 9 Swift UI-test files.
  - `web/src/`: 111 TypeScript source files; `web/test/`: 36 Vitest suites.
  - `android/`: 41 Kotlin app source files and 19 Kotlin test files.
  - `protocol/airdesk.fbs`: 46 top-level `table`/`enum`/`union`/`struct` declarations.
- Verified before this planning pass:
  - iOS: 420 tests, 1 skip, 0 failures.
  - Web: 246 tests across 35 files.
  - Android: 83 tests, `lintDebug` 0 errors / 7 warnings.
  - Core subset: 128 tests via `scripts/check-core.sh`.
  - Protocol conformance and generated-binding drift check.
  - Rust protocol tests: 10 tests.
- Already implemented foundations relevant to the masterplan:
  - AD-PAIR-1, RFC 9383 SPAKE2+ P-256, scrypt registration, QR/PIN envelopes, SAS-gated trust and Iroh `.pairing` channel on iOS/Android; browser equivalents plus WebRTC link/signaling adapters.
  - ADFP typed `ControlHeader`, additive `FabricPayload`, resource RPC opcodes 100–115 and generated Swift/TS/Rust/Kotlin bindings.
  - Capability registry, COSE_Sign1 grants, leases, `cnf` proof, signed revocation snapshots and browser-side provider authorization.
  - Iroh native transport, reliable channels, movement datagrams, path diagnostics and loopback tests.
  - Loopback browser endpoint, generation-safe display reconnect, view-only JPEG surface streaming.
  - Workspace host handoff/degraded mode, sync envelope/AES-GCM, per-sender outbox, LWW/append-log/manual merge.
  - SSH PTY through SwiftNIO SSH.
- Current CI:
  - `protocol.yml`: flatc conformance, Rust protocol tests, web protocol tests.
  - `ios.yml`: xcodegen, build-for-testing, AirDeskTests.
  - `desktop-shell.yml`: `npm run check` and SBOM.
  - `debug-release.yml`: Android and iOS debug artifact release.
  - `android.yml`: Android unit tests, lint and debug assembly.

### 2.2 Landed Phase 0 work

These files entered the initial Phase 0 implementation and are retained here for provenance. They were verified and landed in `4e348e5`:

- Browser pairing:
  - `web/src/identity/pairing-webrtc-session.ts`
  - `web/src/identity/pairing-webrtc.ts`
  - `web/src/identity/index.ts`
  - `web/test/pairing-webrtc-session.test.ts`
  - `web/test/pairing-webrtc.test.ts`
  - `web/test/pairing-signaling.test.ts`
- Android partial data-plane work:
  - `android/app/src/main/java/com/airdesk/android/fabric/FabricTransport.kt`
  - `android/app/src/main/java/com/airdesk/android/fabric/IrohFabricTransportAdapter.kt`
  - `android/app/src/main/java/com/airdesk/android/protocol/AdfpFabricSession.kt`
- Namespace partial work:
  - `AirDesk/Namespace/NamespaceImportService.swift`

Phase 0 is landed. Later changes must keep the full web, iOS, Android, Rust and protocol gates green.

### 2.3 Masterplan corrections and gaps

- The product pins `IrohLib` 1.2.0 in `project.yml` and `iroh-android` 1.2.0 in `android/app/build.gradle.kts`. Only `research/iroh-probe/Cargo.toml` uses `iroh = 1.4.1`. P1-09 verified on 2026-11-12 that no `iroh-ffi` or `iroh-android` `1.3.x`/`1.4.x` release exists; the product pins remain unchanged. `docs/research/iroh-product-upgrade-2026-11-12.md` records the availability, path/network APIs and live-roaming gaps.
- P1-10 now records `cpu_percent`, peak RSS where available, commit/dirty, build/runtime, host model, CPU, memory and network in loopback T1-T4 results. The 2026-11-12 repeat used `Deno.cpuUsage()` for T1/T2 and `/usr/bin/time -l` for T3/T4; `docs/research/transport-metadata-2026-11-12.md` summarizes the dirty harness-validation runs. LAN, cellular, relay, physical-device and cross-host qualification remain P5-06.
- `protocol/rust/` currently contains packed/movement codecs, not a shared core or FFI layer.
- `libghostty-vt`, WebMCP, UWB discovery and zero-copy media capture are not present in tracked source. ADR-027 evaluated `libghostty-vt` and retained WTerm plus the `@wterm/ghostty` core; OSC 133 handling and `renderingPaused` are present in the WTerm path. ResourceCompound and BLAKE3 blob handles, plus the one-euro pointer filter, are implemented and covered by cross-language fixtures.
- The current app target is iOS 17.5 with Mac Catalyst disabled. `ScreenCaptureKit` is a macOS API and cannot be used by the current iOS host target. The host strategy must choose ReplayKit/broadcast extension, a separate macOS host target, or an external host process before implementation.
- ADR-013 is `Proposed`; `XPORT-02` cannot be signed off without measurements.
- ADR-014 deliberately keeps the browser endpoint loopback-only. Non-loopback browser transport is an architecture decision, not a host-binding change.
- ADR-018 is still `Proposed`; a WIT package and host ABI do not exist.
- Android CI exists and is green; parity claims still require hardware qualification and live-network evidence.
- The web terminal has `readText()`, OSC 133 command blocks and `renderingPaused` integration for inactive WinBox panes, but no WebMCP authorization layer.
- Native capability descriptors exist and the cross-platform `DeviceAgent` contract/fixture is implemented, but automatic workspace signing-key distribution and native lease/invocation enforcement remain gaps.

## 3. Program guardrails

Every task must satisfy these rules:

1. **Contract first.** Add or update schema/contract fixtures before platform implementations.
2. **Additive protocol changes only** until a versioned cutover is approved. `protocol/check.sh` must keep passing.
3. **No cryptographic replacement by assertion.** New Rust implementations must reproduce existing RFC vectors and cross-language fixtures before becoming authoritative.
4. **No silent authority changes.** Pairing remains trust, not workspace ownership. Capability leases remain scoped and revocable.
5. **No hidden data movement.** Remote placement and namespace imports must be explicit and diagnosable.
6. **No sensitive release logging.** No typed text, terminal contents, keys or capability tokens in logs.
7. **Feature flags and rollback.** Every core/cutover/transport change needs a rollback path.
8. **Evidence before ADR promotion.** ADR-013, ADR-014, ADR-018 and any new core ADR stay `Proposed` until the stated gate passes.
9. **Truthful status.** No claim of 100x, 1000x, sub-2 ms, sub-15 ms, hardware support or battery performance without recorded method, matrix and result.

## 4. Parallel workstreams and ownership

Use these lanes to reduce merge conflicts. Shared files are serialization points.

| Lane | Primary ownership | May not edit without coordination |
| --- | --- | --- |
| A: Identity/trust | `web/src/identity/**`, `AirDesk/Identity/**`, `AirDesk/Sync/WorkspaceSyncKey*` | `protocol/airdesk.fbs`, `SessionCoordinator.swift` |
| B: Protocol/transport/remote | `protocol/**`, `AirDesk/Fabric/**`, `AirDesk/Protocol/**`, `AirDesk/Runtime/**`, `AirDesk/Remote/**`, `AirDesk/Namespace/**` | `AirDesk/Capabilities/**` |
| C: Agents/parity | `AirDesk/Capabilities/**`, `AirDesk/Capture/**`, `AirDesk/Resources/**`, `android/**` | `protocol/airdesk.fbs` |
| D: Core/Rust/CI | `core/**`, `protocol/rust/**`, `scripts/build-core-*`, `.github/workflows/core.yml`, `.github/workflows/android.yml` | generated protocol files |
| E: UX/terminal/input | `AirDesk/Input/**`, `AirDesk/Features/**`, `web/src/terminal/**`, `web/src/desktop/**` | `protocol/airdesk.fbs` |
| F: Media/PTY/qualification | `AirDesk/Display/**`, `AirDesk/Remote/SSH*`, `CastReceiver/**`, `scripts/research/**`, `docs/research/**` | `project.yml`, `AppEnvironment.swift` |

Serialization points:

- `protocol/airdesk.fbs` and generated bindings: one schema owner per change, regenerate with `protocol/generate.sh`, run `protocol/check.sh`.
- `AirDesk/App/AppEnvironment.swift`, `AirDesk/Session/SessionCoordinator.swift`: one integration owner at a time.
- `project.yml`: only the dependency owner changes packages; sequence Iroh/OpenSSL/UniFFI changes.
- `milestones.md`, `README.md`, `docs/adr/README.md`: integration owner only.
- `.github/workflows/**`: CI owner only.

## 5. Phase plan and task inventory

Effort is in engineer-weeks and is approximate. Status is `Partial`, `Pending`, `Blocked` or `Research`.

### Phase 0 — Stabilize current P1 and CI (2–3 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P0-01 | Verify and land browser WebRTC pairing orchestration | `web/src/identity/pairing-webrtc-session.ts`, `pairing-webrtc.ts`, `index.ts`; `web/test/pairing-webrtc-session.test.ts`, `pairing-webrtc.test.ts`, `pairing-signaling.test.ts` | Full-checkout `npm run check` passes; binding mismatch rejects before SAS; malformed/duplicate/out-of-order signals covered; no live signaling server claimed | — | Verified, committed |
| P0-02 | Verify or revert Android fabric/ADFP partials | `android/.../fabric/FabricTransport.kt`, `IrohFabricTransportAdapter.kt`, `protocol/AdfpFabricSession.kt`; `android/app/src/test/.../IrohFabricTransportAdapterTest.kt`, `AdfpFabricSessionTest.kt` | Remote `testDebugUnitTest`, `lintDebug`, `assembleDebug` pass; 1 MiB cap and channel routing enforced; pairing path unchanged | P0-04 | Verified, committed |
| P0-03 | Verify or revert namespace partial | `AirDesk/Namespace/NamespaceImportService.swift`; `AirDeskTests/NamespaceImportServiceTests.swift` | Compiles in AirDeskTests; path/symlink/lease/fid tests pass; not wired into production | — | Verified, committed |
| P0-04 | Add Android CI | `.github/workflows/android.yml`, `android/gradle.properties` if needed | JDK 17 + Android SDK 35; `testDebugUnitTest`, `lintDebug`, `assembleDebug` on push/PR paths | — | Verified, first run green |
| P0-05 | Add shared-core boundary ADR | `docs/adr/024-shared-core-and-ffi-boundary.md`, `docs/adr/README.md` | ADR is `Accepted`; defines what may move into Rust, compatibility fixtures, rollback and ownership | P0-01..03 | Accepted |
| P0-06 | Freeze Phase 1 contracts | `protocol/fixtures/**`, `docs/planning/100x-masterplan-execution.md`, `milestones.md` | ADFP envelope, remote runtime, DeviceAgent and WIT contracts have named owners and fixture paths | P0-01..05 | Contract paths frozen; ADFP, ResourceCompound/blob, movement/one-euro, remote runtime provider, DeviceAgent and WIT fixtures verified |

#### Phase 1 contract freeze (P0-06)

| Contract | Owner | Fixture path(s) | Frozen shape | Consumers |
| --- | --- | --- | --- | --- |
| ADFP envelope v1 | Protocol owner | `protocol/fixtures/adfp/envelope-v1.json`, `protocol/fixtures/adfp/payloads-v1.json` | File identifier `ADEN`, envelope version `1`, 1 MiB maximum, typed header with expiry/correlation/idempotency, reliable-channel map | Swift, TypeScript, Rust, Kotlin |
| ResourceCompound and blob handles | Protocol owner | `protocol/fixtures/resource-compound/*.json`, `protocol/fixtures/resource-blob/*.json` | Additive compound Walk/Open/Read/Clunk semantics; >64 KiB results return a versioned BLAKE3 handle | Swift, TypeScript, Rust, Kotlin |
| Remote runtime lifecycle | Runtime owner | `protocol/fixtures/remote-runtime/lifecycle-v1.json` | Create/start/suspend/checkpoint/resume/stop/destroy/status, disconnect preservation and typed transport/authorization failures | Swift, TypeScript |
| DeviceAgent contract | Capabilities owner | `protocol/fixtures/device-agent/contract-v1.json` | Identity, capability descriptors, request/release, subscription, health, typed lifecycle and platform-denial results | Swift, TypeScript, Kotlin |
| Host ABI WIT | Runtime and security owners | `protocol/fixtures/host-abi/wit-v1.json` | `airdesk:host-abi@0.2.0`, WASI 0.2 baseline, VFS/PTY/display interfaces, per-runtime qualification, no display frame submission | Swift, Rust, Wanix, browser |
| Movement and one-euro filter | Input owner | `protocol/fixtures/input/one-euro-v1.json` | Deterministic pointer/movement normalization and filter outputs with no phase lag at high speed | Swift, TypeScript, Rust |

Compatibility rules:

- A fixture path is a contract even before its first file exists; the consuming task is blocked until the fixture and owner are present.
- A fixture change is a compatibility change and requires review from every consumer owner.
- No consumer may claim cross-language parity from a round-trip test alone; invalid, truncated, oversized and wrong-version fixtures are mandatory.
- `protocol/check.sh` verifies schema conformance and generated bindings; fixture equality is a separate CI gate owned by the protocol owner.

### Phase 1 — Trust, protocol and remote foundation (12–16 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P1-01 | Production signaling adapter and loopback harness | `web/src/identity/pairing-signaling.ts`, `pairing-webrtc-session.ts`; new signaling transport tests | Host/controller exchange real offer/answer/candidates through an injected transport; closed/malformed/duplicate signals fail typed; no plaintext secret in signaling | P0-01 | Verified, committed |
| P1-02 | Automatic workspace signing-key distribution | `AirDesk/Sync/WorkspaceSyncKeyStore.swift`, `WorkspaceSyncRuntime.swift`, `AirDesk/Identity/PairingLiveSession.swift`; `web/src/identity/session-keys.ts`, `web/src/sync/**` | After SAS, peers derive/exchange the workspace signing key; revoked peers cannot receive or use it; cross-platform fixture passes | P0-01, P1-01 | Verified, committed |
| P1-03 | ADFP production envelope codec | `AirDesk/Protocol/ADFPEnvelopeCodec.swift`; `AirDesk/Fabric/IrohFabricInputCodec.swift`, `IrohFabricPeer.swift`; `web/src/protocol/**`; `protocol/rust/src/**`; Android `AdfpFabricSession.kt` | Reliable channels carry validated envelopes; file id/version/size/expiry/correlation/idempotency enforced; golden fixtures match across Swift/TS/Rust/Kotlin | P0-02, P0-06 | Verified, committed |
| P1-04 | ResourceCompound and blob handle protocol | `protocol/airdesk.fbs`, `protocol/baseline/airdesk_v1.fbs`, `protocol/fixtures/resource-compound/*.json`, `protocol/fixtures/resource-blob/*.json` | Additive schema; compound Walk/Open/Read/Clunk has one-RTT semantics; >64 KiB result can return BLAKE3 handle; all generated bindings and conformance pass | P1-03 | Verified, committed |
| P1-05 | Remote runtime provider | `AirDesk/Runtime/RemoteRuntimeProvider.swift`, `RuntimeRegistry.swift`, `RuntimeProvider.swift`; `AirDeskTests/RemoteRuntimeProviderTests.swift` | Lifecycle maps create/start/suspend/checkpoint/resume/stop/destroy/status; disconnect preserves observed state; typed transport/authorization errors; not default-enabled | P1-03 | Verified, committed |
| P1-06 | Placement integration and diagnostics | `AirDesk/Runtime/RuntimeRegistry.swift`, `AirDesk/Workspace/WorkspaceOrchestrator.swift`, `ApplicationLifecycleController.swift`; `web/src/remote/placement.ts` | Deterministic local/device/runtime selection; explicit device filter; typed unavailable/transport/authorization failures; diagnostics explain selection | P1-05 | Verified, committed |
| P1-07 | Capability-scoped remote terminal | `AirDesk/Remote/CapabilityScopedTerminal.swift`, `RemoteTerminalController.swift`, `SessionCoordinator.swift`; `AirDeskTests/CapabilityScopedTerminalTests.swift` | Connect requires matching unexpired lease; denied/revoked/busy are typed and auditable; no capability bypass through terminal profile | P1-03, P1-05 | Verified, committed |
| P1-08 | Resource RPC and scoped namespace import | `AirDesk/Protocol/ResourceRPCClient.swift`, `ResourceRPCServer.swift`, `AirDesk/Namespace/NamespaceImportService.swift`; `AirDeskTests/ResourceRPCTests.swift`, `NamespaceImportTests.swift` | All opcodes, fid lifecycle, path confinement, symlink escape, size caps and lease denial/revocation covered; no 9P2000 tunneling; chunked transfer for large payloads | P0-03, P1-04 | Verified, committed |
| P1-09 | Iroh product upgrade spike | `project.yml`, `android/app/build.gradle.kts`, `AirDesk/Fabric/**`, `research/iroh-probe/` | Verify IrohLib/FFI 1.4.x availability; document API gaps; test path migration/roaming and relay diagnostics on loopback before product pin changes | P0-04 | Research (no pin change; self-built 1.4 allowed only with existing language targets and qualification) |
| P1-10 | Transport evidence upgrade | `scripts/research/transport_bench.ts`, `run-transport.sh`, `run-iroh*.sh`, `research/scenarios/**`, `docs/research/runs/**` | `cpu_percent`, build/runtime/network/device metadata; p50/p95/p99 recorded; no claim without method | P0-04 | Verified, committed |

### Phase 2 — Agent parity and ABI (16–22 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P2-01 | Cross-platform `DeviceAgent` contract | `AirDesk/Capabilities/DeviceAgent.swift`, `android/.../agent/DeviceAgent.kt`, `web/src/capability/**`; shared fixtures | Identity, capabilities, request/release, subscribe, health and typed lifecycle on all clients; availability and authorization remain independent | P0-06 | Verified, committed |
| P2-02 | iOS camera capture streaming | `AirDesk/Capture/CameraCaptureSource.swift`, `CameraCaptureStreamController.swift`; tests with mock source | Explicit authorization/lease gate; bounded frames/backpressure; cancel and permission-denied typed; no physical camera required for unit tests | P2-01 | Verified, committed |
| P2-03 | iOS document roots and file transfer | `AirDesk/Resources/ResourceRoot.swift`, `ResourceTransferService.swift`; tests | App-scoped/user-selected roots; path/symlink confinement; bounded read/write/stat; transfer events; no device-wide access | P2-01 | Verified, committed |
| P2-04 | Native capability lease and invocation enforcement | `AirDesk/Capabilities/CapabilityLeaseManager.swift`, `CapabilityAuthorizer.swift`, `CapabilityInvocationService.swift` | Issuance/expiry/revocation; provider/root issuer checks; remote invocation denied without matching lease/`cnf`; audit event | P2-01, P1-02 | Verified, committed |
| P2-05 | Android agent contract and canonical URIs | `android/.../agent/DeviceAgent.kt`, `capabilities/**`, `protocol/AdfpCapabilityMapper.kt` | Canonical `airdesk://fs/documents/read` plus `write`; camera authorization aligned with ADR-012; tests | P2-01 | Verified, committed |
| P2-06 | Android precision input controller | `AndroidTrackpadSurface.kt`, `AndroidInputRouter.kt`, `InputLease*` equivalents; tests | 120 Hz local cursor path; packed movement; no stuck input; multi-controller arbitration | P2-01, P4-01 | Verified, committed |
| P2-07 | Android workspace/terminal bridge | `AndroidWorkspaceHost.kt`, `AndroidDesktopBridge.kt`, `DisplaySessionController.kt`; tests | Bundled DesktopShell drives workspace host and terminal bridge; reconnect preserves identity; truthful diagnostics | P1-05, P2-01 | Verified, committed |
| P2-08 | Android MediaProjection/MediaCodec stream | `AndroidMediaCodecStream.kt`, `DisplaySessionController.kt`; tests | Registered display pipeline; hardware codec capability detection; fallback and typed failure; physical qualification separate | P2-07 | Verified, committed |
| P2-09 | Android persistent SSH service | `AndroidSSHService.kt`, `RemoteSSH*`; tests | Foreground service; reattach and second-device handoff use same protocol as iOS; process survival tested remotely | P1-07 | Code complete; physical survival gate pending |
| P2-10 | WIT host ABI 0.2 | `protocol/abi/wit/airdesk-host-abi.wit`, `protocol/abi/README.md`, `protocol/abi/check.sh` | `vfs-service`, `pty-service`, `display-sink`, typed errors, lease revalidation, 256 KiB PTY credits, no display frame submission | P2-01 | Verified, committed |
| P2-11 | WIT 0.3 evaluation and conformance | `protocol/abi/wit/airdesk-host-abi-0_3.wit`, `protocol/abi/conformance/**` | Separate 0.3 world using `stream<T>`/`future<T>`; no mixed worlds; conformance harness runs where tooling exists | P2-10 | Static gate complete; runtime conformance pending |

### Phase 3 — Shared Rust core extraction (20–30 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P3-01 | Create core workspace | New `core/Cargo.toml`, `core/rust-toolchain.toml`, `core/airdesk-core/`, `core/airdesk-ffi/`, `core/airdesk-wasm/`, `core/airdesk-protocol/`; `.github/workflows/core.yml` | ADR-024 approved for implementation; crates build; no existing code deleted | P0-05 | Verified, committed |
| P3-02 | Move low-risk codecs | `protocol/rust/src/packed.rs`, `movement.rs`, `lib.rs`; `core/airdesk-protocol/**`; fixtures | Packed/movement byte equality across Swift/TS/Rust; existing tests continue; protocol crate re-exports or compatibility shim | P3-01 | Pending |
| P3-03 | Move ADFP envelope/resource codec | New `core/airdesk-protocol/src/envelope.rs`, `resource.rs`; shared fixtures | Golden bytes and malformed-frame corpus match Swift/TS/Kotlin; Rust becomes reference but not yet sole source | P1-03, P1-04, P3-02 | Pending |
| P3-04 | Extract pairing transcript/key schedule | New `core/airdesk-pairing/**`; `protocol/fixtures/ad-pair-1.json` | AD-PAIR-1 transcript, HKDF schedule, SAS and scrypt registration match existing Swift/TS/Kotlin fixtures | P3-01 | Pending |
| P3-05 | Evaluate Rust SPAKE2+ implementation | `core/airdesk-pairing/**`; RFC 9383 vectors | `confirmV`-first, cofactor/subgroup checks, zeroization and error handling proven; no product cutover until independent review | P3-04 | Research (RFC vectors + independent review required) |
| P3-06 | UniFFI Swift/Kotlin bindings | `core/airdesk-ffi/**`, `scripts/build-core-apple.sh`, `scripts/build-core-android.sh`, `project.yml`, `android/app/build.gradle.kts` | Generated bindings build in CI; app can call a non-authoritative core smoke API behind a flag | P3-02, P3-03 | Pending |
| P3-07 | WASM component target | `core/airdesk-wasm/**`, `web/src/core/**` | Deterministic wasm builds; web uses only smoke/adapter path; no TypeScript crypto removal yet | P3-03 | Pending |
| P3-08 | Feature-flagged cutover | `AirDesk/Core/**`, `web/src/core/**`, `android/.../core/**`, settings/diagnostics | Per-feature flags for movement, envelope, pairing and sync; rollback to native path; telemetry reports active path | P3-06, P3-07 | Pending |
| P3-09 | Remove duplicated implementations | Delete/replace only after equivalence and one release cycle; `README.md`, `milestones.md`, ADR updates | Duplicate code paths removed with no regressions; rollback tag retained | P3-08, P1-10 | Pending |

### Phase 4 — Input, terminal, sync and UX (14–20 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P4-01 | One-euro pointer filter | `AirDesk/Input/PointerState.swift`, `InputDispatcher.swift`, `protocol/rust/src/movement.rs`, `web/src/protocol/movement.ts`; tests | Deterministic filter fixture; no phase lag at high speed; native/web output matches | P0-06 | Verified, committed |
| P4-02 | Decoupled local cursor and host suppression | `AirDesk/Input/AirCursorView.swift`, `MacTrackpadView.swift`, `InputDispatcher.swift`, `AirDesk/Display/**`; protocol cursor shape/hotspot | Local cursor renders at display rate; remote cursor shape/hotspot arrives out of band; no double cursor; host suppression verified | P4-01 | Verified, committed |
| P4-03 | Semantic input deck | `AirDesk/Features/Keyboard/SemanticInputDeck.swift`, `KeyboardBar.swift`, `MacInputDeck.swift`, `HardwareKeyboardCapture.swift`; OSC 133 state input | Context modes A/B/C/D drive bars and gestures; no modal preview dependency; all actions have capability/lease checks | P4-02 | Verified, committed |
| P4-04 | Continuity pill and haptics | `AirDesk/Features/Session/SessionContinuity.swift`, `SessionContinuityPill.swift`, `SessionRecoveryView.swift`, `RootView`/`AppEnvironment`, `AirDesk/Design/Haptics.swift`; telemetry overlay | Non-blocking connection/latency/capability pill; path migration status; haptics only for semantic events; recovery screen removed or fallback-only | P1-05, P1-09 | Verified, committed |
| P4-05 | Ambient proximity pairing | `AirDesk/Discovery/BonjourDiscovery.swift`, new `NearbyInteractionDiscovery.swift`; `android/.../discovery/UwbDiscovery.kt`; `web/src/identity/pairing-signaling.ts` | Bonjour and UWB proximity offer gated by distance/angle; manual code remains fallback; privacy/threat model covers proximity leakage | P0-01, P4-04 | Research (physical UWB matrix required) |
| P4-06 | Onboarding collapse | `AirDesk/Features/Onboarding/*`, `AirDesk/Identity/PairingCoordinator.swift`, `Settings/PairingSettingsView` | Proximity/one-tap path reaches workspace without five screens; manual flow remains in advanced fallback; accessibility tests | P4-05 | Code complete (one-tap); proximity gate pending |
| P4-07 | Terminal engine decision and standardization | `web/src/terminal/**`, `web/package.json`, `AirDesk/Web/TerminalBridge.swift`; research ADR | Benchmark libghostty-vt/@wterm/ghostty against current engine for size, VT coverage, selection, accessibility and license; decide before replacement | P0-06 | Verified, committed (ADR-027) |
| P4-08 | Semantic command blocks | `web/src/terminal/terminal-engine.ts`, `wterm-engine.ts`, new `semantic-blocks.ts`; `AirDesk/Web/TerminalBridge.swift` | OSC 133 blocks, exit aura, copy output, markdown view and unconfirmed-input safety; no automatic retry | P4-07 | Verified, committed (web) |
| P4-09 | Read-only agent supervision | `web/src/terminal/**`, `web/src/desktop/**`, `AirDesk/Workspace/ApplicationLifecycleController.swift` | Agent state badges; read-only text snapshots; write/inject requires explicit capability; no prompt/secret leakage | P4-08, P2-04 | Verified, committed (web + native model) |
| P4-10 | WinBox rendering and tiling | `web/src/desktop/winbox.ts`, `window-manager.ts`, `shell-runtime.css` | GPU-transform-only movement, layout/style/paint containment, `renderingPaused` for inactive panes, BSP/ribbon layout | P4-07 | Verified, committed (web + desktop shell) |
| P4-11 | Operation-based workspace sync | `AirDesk/Sync/WorkspaceSyncMerge.swift`, `web/src/sync/merge.ts`, `protocol/airdesk.fbs`; new core sync crate | Operation log with Lamport/actor ordering; deterministic offline/multi-writer convergence; existing merge fixtures preserved or migrated with ADR | P3-03, P1-02 | Research (wait for P3-03) |
| P4-12 | Window sling | `web/src/remote/placement.ts`, `web/src/remote/window-projection.ts`, `AirDesk/Cast/WindowProjection.swift`, `AirDesk/Cast/CastSessionCoordinator.swift`, `android/.../workspace/WindowProjection.kt`, `android/.../PresentationScreen.kt` | Window detach/project to paired Cast/browser/Android target; compute stays on host; reconnect restores window identity; hardware gate | P1-06, P4-10 | Code complete (lifecycle model); live projection + hardware gate pending |

### Phase 5 — Media, persistent PTY and qualification (12–20 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P5-01 | Host capture platform decision | New ADR-025; `AirDesk/Display/**`, `project.yml` | Decision records iOS ReplayKit/broadcast extension vs separate macOS host vs external host; ScreenCaptureKit only if a macOS target exists | P0-05 | Verified, committed |
| P5-02 | Zero-copy encoder pipeline | `AirDesk/Display/ScreenCapturePipeline.swift`, `VideoToolboxEncoder.swift`, `DisplayCoordinator.swift`; `android/.../AndroidMediaCodecStream.kt` | Capture surface -> encoder with bounded queues; HEVC/AV1 capability detection; keyframe/recovery; no unbounded memory | P5-01 | Verified, committed (iOS host path) |
| P5-03 | Client decode and frame pacing | `AirDesk/Display/DesktopSurface.swift`, `DisplayCoordinator.swift`; web endpoint surface path | Pacing to display refresh; dropped-frame diagnostics; latency/CPU metrics; no false glass-to-glass claim | P5-02 | Verified, committed (iOS decode/pacing path) |
| P5-04 | Persistent PTY daemon | New `core/airdeskd/**`, `AirDesk/Remote/PersistentTerminalFabric.swift`, `AirDesk/Remote/SSHPTYSession.swift`, `RemoteTerminalController.swift`; tests | `airdeskd` byte-tees raw PTY over ADFP; multiple clients attach; replay buffer bounded; leases enforced | P1-03, P1-07 | Verified, committed (daemon/codec) |
| P5-05 | OSC 133 replay and handoff | `AirDesk/Remote/**`, `AirDesk/Web/TerminalBridge.swift`, `AirDeskTests/RemoteSSHReattachTests.swift` | Reconnect replays active command records without corrupting TUIs; second device attaches; zero lost acknowledged bytes | P4-08, P5-04 | Verified, committed (replay/handoff model) |
| P5-06 | XPORT-01/02 qualification | `scripts/research/**`, `research/scenarios/**`, `docs/research/**`, `docs/adr/013-multi-transport-and-connectivity.md` | CPU, reconnect, direct/relay and device matrix recorded; ADR-013 updated only if evidence supports it | P1-10, P5-02 | Blocked |
| P5-07 | Physical device matrix | Hardware test plans under `docs/research/`; no code claim | iPhone/iPad/Android/Cast/AirPlay/external display tested with documented limitations | P5-06 | Blocked |
| P5-08 | Network and battery matrix | Same | 5 GHz Wi-Fi, cellular, tailnet, relay; battery/thermal recorded; no fabricated targets | P5-07 | Blocked |
| P5-09 | Cast/AirPlay/external display | `CastReceiver/**`, `AirDesk/Cast/**`, `AirDesk/Display/**` | Physical hardware qualification or explicit deferral; no production claim without hardware | P5-07 | Blocked |

## 6. Dependency graph

Critical path:

```
P0-04 Android CI ──> P0-02 Android partials
P0-01 web pairing ─> P1-01 signaling ─> P1-02 signing key
P0-06 contracts ──> P1-03 ADFP ──> P1-04 ResourceCompound/BLOB ──> P1-08 Resource RPC
                               └──> P1-05 remote runtime ──> P1-06 placement ──> P1-07 remote terminal
P1-03 ──> P2-01 DeviceAgent ──> P2-02..09
P1-03/04 ──> P3-03 core envelope/resource ──> P3-06 FFI ──> P3-08 cutover
P3-04/05 pairing core ──> P3-08 cutover
P2-01 ──> P2-10 WIT ──> P2-11 WIT 0.3
P4-01 ──> P4-02 ──> P4-03
P4-07 ──> P4-08 ──> P4-09
P5-01 ──> P5-02 ──> P5-03
P5-04 ──> P5-05
P5-01..05 + P1-10 ──> P5-06 ──> P5-07..09
```

Do not start P3-04/05 crypto extraction before P3-03 fixture equality and P0-05 ADR approval. Do not remove any existing implementation until P3-08 has shipped and rolled back cleanly once.

## 7. Verification and CI gates

### Existing commands

| Area | Command | Environment | Gate |
| --- | --- | --- | --- |
| Protocol | `./protocol/check.sh` | Ubuntu with pinned flatc 25.12.19 | Schema, baseline conformance, generated drift |
| Rust codec | `cargo test --manifest-path protocol/rust/Cargo.toml` | Ubuntu | Packed/movement/ADFP fixtures |
| Web | `npm run check` | macOS or Ubuntu, Node 22 | Typecheck, lint, tests, build, licenses |
| Web SBOM | `npm run sbom` | CI | SBOM artifact |
| iOS | `./scripts/ci-ios.sh` | macOS 15, Xcode 16.4 | Build-for-testing + AirDeskTests |
| Core subset | `./scripts/check-core.sh` | macOS | Workspace/input subset |
| Android | `./gradlew testDebugUnitTest lintDebug assembleDebug` | Ubuntu + JDK 17 + SDK 35 | Unit, lint, APK |
| Release | `.github/workflows/debug-release.yml` | GitHub Actions | Debug artifacts and prerelease |

### Required new checks

| Check | Adds | Gate |
| --- | --- | --- |
| Android CI | `android.yml` | Blocks Android parity regressions |
| ADFP golden vectors | `protocol/fixtures/adfp/envelope-v1.json`, malformed corpus | Swift/TS/Rust byte equality; Kotlin semantic decode and round-trip |
| ResourceCompound/blob fixtures | `protocol/fixtures/resource-compound/*.json`, `protocol/fixtures/resource-blob/*.json` | Cross-language round-trip and bounds |
| DeviceAgent contract | `protocol/fixtures/device-agent/contract-v1.json` | Identity/capability/request-release/subscription/health/lifecycle shape and typed denials |
| WIT conformance | `protocol/abi/check.sh` | 0.2 world validity; 0.3 separate; no mixed worlds |
| Core FFI smoke | `core.yml` | Rust tests, UniFFI bindings, wasm build, Swift/Kotlin smoke |
| Transport evidence | Structured run JSON | Required metadata present; no unrecorded result |
| Capability negative tests | iOS/Android/web | Denied/expired/revoked/busy fail closed |

### P1-02 verification evidence

- After SAS, the host sends the current workspace synchronization key to the newly paired peer as a `workspace-key-grant` v1 message authenticated with the pairing-derived bootstrap key. The controller accepts only a trusted issuer, the matching workspace, a valid 32-byte key and a non-stale generation.
- Existing trusted peers receive `workspace-key-rotation` v1 messages authenticated under the current workspace key. Revocation rotates the key, clears the local outbox, queues one pending rotation per trusted endpoint and persists the key generation plus pending rotations in Keychain-backed state.
- The receiver rejects replayed, skipped, wrong-issuer, wrong-workspace and tampered rotations; revoked peers fail AES-GCM authentication after rotation. Replayed grants are idempotent and cannot lower the accepted generation.
- Cross-platform fixtures `protocol/fixtures/sync/key-grant-v1.json` and `protocol/fixtures/sync/key-rotation-v1.json` reproduce the same nonce and ciphertext in Swift and TypeScript.
- iOS: full `xcodebuild test` passed; 511 tests, 1 skipped, 0 failures, including 6 `WorkspaceSyncKeyRotationTests`.
- Web: full `npm run check` passed; 278 tests across 40 files, including 5 `sync-key-rotation.test.ts` cases.
- Android, Rust and protocol schema/generated bindings were unchanged by P1-02. The distributed key is the workspace synchronization AES-GCM key; capability signing/issuer enforcement remains P2-04. No live multi-device network or hardware qualification is claimed.

### P4-03 verification evidence

- `SemanticInputDeck.swift` maps extended, mirrored, cast and preview sessions to context modes A/B/C/D; any non-ready session resolves to D. Mode A/C expose the dock action, mode B hides it, and disconnected mode D exposes reconnect, diagnostics and end-session recovery actions.
- `SemanticInputAuthorizationContext` denies actions unless the session is ready, the mode allows the action, all required capabilities are available and the active controller holds the local input lease with a non-zero epoch. Recovery actions intentionally bypass readiness and lease checks. `SessionCoordinator.performSemanticAction` rechecks authorization before dispatching any key or recovery action.
- `OSC133Parser` consumes prompt (`A`), input (`B`), running (`C`) and finished (`D` with optional exit code) sequences from remote terminal data, including BEL and `ESC \` terminators and sequences split across chunks. Session preparation resets the parser and phase. Command-block presentation is now P4-08; the bundled-shell terminal path remains unwired.
- `MacInputDeck` and `KeyboardBar` render the mode/terminal status and mode-aware action row; hardware keyboard capture is gated by `canUseDesktopControls`. The deck keeps its fixed 620-point height by reducing the trackpad to 220 points.
- iOS: full `xcodebuild test` passed; 543 tests, 1 skipped, 0 failures, including 5 `SemanticInputDeckTests` and the `SessionCoordinatorLeaseTests` semantic authorization case. Web, Android and Rust were unchanged. No physical-device or bundled-terminal semantic-phase qualification is claimed.

### P4-02 verification evidence

- `LocalCursorPresentation` keeps the local pointer target independent of host video frames and exposes a display-rate `TimelineView(.animation)` overlay. A 120 Hz maximum frame clock coalesces multiple pointer updates into the latest rendered point, so input cadence does not drive cursor rendering.
- `CursorMetadata` is an out-of-band control payload carrying session/generation/sequence, cursor shape, normalized hotspot and visibility. Validation rejects mismatched sessions/generations, stale sequences, non-finite or out-of-range hotspots and contradictory hidden-visible metadata. `SessionCoordinator.applyCursorMetadata` is the transport handoff point.
- The local cursor suppresses the host cursor on session start by sending a `cursor` control with `hostVisible: false`, restores it on disable/end, and ignores remote-cursor visibility while the local cursor is active. The bundled DesktopShell consumes the control, tracks `hostCursorSuppressed`, and prevents `moveCursor`/session activation from re-showing its virtual cursor. This avoids drawing both cursors.
- `MirroredDesktopView` mounts `LocalCursorOverlay` above `DesktopSurfaceAnchor` with hit testing disabled. Shape and hotspot changes come from out-of-band metadata; the overlay itself never waits for a decoded display frame.
- iOS: full `xcodebuild test` passed; 537 tests, 1 skipped, 0 failures, including 5 `LocalCursorPresentationTests`. Web `npm run check` passed with 283 tests across 40 files. The `cursor` control payload is a native JSON bridge message; ADFP FlatBuffers cursor-shape parity and physical-display qualification are not claimed.

### P2-06 verification evidence

- `PackedMovementFrame` in the Android input package encodes and decodes the shared 16-byte v12 layout: magic `0xA5`, flags/epoch/sequence/coordinates/buttons/modifiers, with little-endian floats and uint32 sequence. The committed `protocol/fixtures/movement-v12.json` round-trips byte-for-byte, and wrong length, flags, coordinate range, magic and button masks are rejected.
- `InputLeaseRegistry` scopes leases to `airdesk://input/pointer`, validates controller/workspace/application/session/epoch/audit fields and timestamps, and arbitrates one active controller with typed `LEASE_DENIED`, `LEASE_BUSY`, `LEASE_REVOKED`, `LEASE_EXPIRED` and `LEASE_INVALID` failures.
- `AndroidInputRouter` coalesces pointer movement at a 120 Hz frame interval, clamps a normalized local cursor, increments frame sequence and emits packed frames through an injectable sink. Revocation, expiry and surface deactivation emit a zero-button release frame before clearing the lease so held buttons cannot stick.
- `AndroidTrackpadSurface` is a reusable Compose surface that drives the router from `withFrameNanos` and forwards raw pointer deltas without touch-slop batching. It is not yet mounted over the presentation WebView, and no production remote packed-frame transport is wired.
- Android: full `testDebugUnitTest lintDebug assembleDebug --rerun-tasks` passed; 166 tests, 0 failures, including 2 `PackedMovementFrameTest` and 5 `AndroidInputRouterTest` cases. `lintDebug` reports 0 errors and 8 pre-existing warnings. No physical-device, multitouch or remote-input qualification is claimed.

### P4-01 verification evidence

- Native `OneEuroFilter`, TypeScript `OneEuroFilter` and Rust `OneEuroFilter` implement the same adaptive low-pass filter with `minCutoff=1.0`, `beta=160.0`, `dCutoff=1.0` and a 1/240 s minimum delta. The higher beta is tuned for normalized pointer coordinates so high-speed movement raises the cutoff instead of introducing material positional lag.
- `protocol/fixtures/input/one-euro-v1.json` is generated from the shared algorithm and contains low-speed jitter and high-speed tracking cases. Swift, TypeScript and Rust reproduce the expected outputs within 1e-9.
- `PointerState` enables the filter by default while retaining the existing sensitivity/acceleration gain and a `filterEnabled: false` path for raw movement. `setPosition` and `center` reset filter state. Existing session input uses the default `PointerState`, so the filter is on the production cursor path.
- Fixture assertions require high-speed warmup error below 0.005 and final error below 0.003 normalized units, while low-speed jitter output range stays below 20% of the raw range.
- iOS: full `xcodebuild test` passed; 532 tests, 1 skipped, 0 failures, including 5 `OneEuroFilterTests` and the updated `PointerStateTests`.
- Web: full `npm run check` passed; 283 tests across 40 files, including 8 movement/one-euro cases. Rust: `cargo test` passed; 22 tests, including 5 one-euro tests. Android was unchanged.

### P2-04 verification evidence

- `CapabilityLeaseManager` issues native capability leases only within a signed grant's capability URI, operations, epoch and validity window, rejects duplicate lease IDs and supports expiry checks and revocation. Lease requests remain scoped to workspace, application, requester, session and audit IDs.
- `CapabilityGrant` uses a deterministic native binary claims token with Ed25519/P-256 signatures verified through `DevicePublicKey`. `CapabilityAuthorizer` validates the full root/delegated chain, approved root issuer, audience, epoch, parent token hash, subject/issuer linkage, validity windows and attenuation of capability URI, operations and expiry. This native token format is not COSE_Sign1 and does not claim cross-platform grant parity.
- `CapabilityRevocationStore` enforces monotonic sequence numbers, retained prior entries, trusted issuers and freshness windows. Grant and lease revocation references are checked independently before authorization.
- Proof of possession uses the `AD-CAP-POP-1` challenge domain over the final grant token hash plus nonce and the `cnf` SHA-256 SPKI thumbprint. Missing, mismatched and tampered proofs are rejected.
- `CapabilityInvocationService` authorizes before dispatch, denies missing/revoked/expired leases and context or operation mismatches, and records allowed/denied/expired/revoked audit events with invocation, grant, lease, workspace, application, requester, session and payload metadata. It is not yet wired into a production remote-invocation transport.
- iOS: full `xcodebuild test` passed; 526 tests, 1 skipped, 0 failures, including 10 `CapabilityLeaseInvocationTests` covering issuance bounds, expiry, manager and snapshot revocation, stale revocation data, root/parent/attenuation checks, proof-of-possession and audit output.
- Web: full `npm run check` passed; 278 tests across 40 files. Android, Rust and protocol schema/generated bindings were unchanged by P2-04.

### P1-08 verification evidence

- `ResourceRPCCodec`, `ResourceRPCClient` and `ResourceRPCServer` encode and decode every ADFP-local resource request/result opcode 100–117. Incoming result opcodes and non-FlatBuffer frames, including 9P2000-shaped buffers, are rejected; there is no 9P2000 tag or wire passthrough.
- The server dispatches attach/walk/open/read/write/clunk/stat/wstat/compound to `NamespaceImportService`. Typed `NamespaceError` values map to `ResourceStatus`, and individual-op failures return a compound result with the failing status.
- Fid lifecycle, bind-mode permissions, lease denial/expiry/revocation and lease path prefixes remain enforced by the existing service and lease registry. Path confinement rejects absolute paths, parent traversal and empty/oversized segments; the confined filesystem backend rejects symlink escapes outside the root.
- Reads and writes are capped at 64 KiB per operation. `readAll`/`writeAll` chunk larger transfers client-side, and tests assert every wire request stays within the bound. Server request frames over the configured cap fail with `invalid`.
- iOS: full `xcodebuild test` passed; 516 tests, 1 skipped, 0 failures, including 5 `ResourceRPCTests` covering all opcodes, fid lifecycle, path/symlink confinement, chunking, size caps and lease denial/revocation.
- Web: full `npm run check` passed; 278 tests across 40 files. Android, Rust and protocol schema/generated bindings were unchanged by P1-08.

### P1-03 verification evidence

- Web: `npm run check` passed; 262 tests across 37 files, including 6 ADFP fixture tests.
- iOS: `xcodebuild test` passed; 434 tests, 1 skipped, 0 failures, including 4 `ADFPEnvelopeCodecTests` and 6 `IrohFabricInputCodecTests`.
- Android: `testDebugUnitTest lintDebug assembleDebug` passed; 107 tests, 0 failures, including ADFP fixture and session tests.
- Rust: `cargo test` passed; 13 tests, including ADFP fixture, malformed-input and round-trip tests.
- Swift/TS/Rust reproduce fixture input/control envelopes byte-for-byte. Kotlin decodes and re-encodes semantically because generated builder field ordering is not byte-identical.

### P1-04 verification evidence

- Protocol: `./protocol/check.sh` passed after regenerating Swift, TypeScript, Rust and Kotlin bindings; readonly drift check passed.
- Web: `npm run check` passed; 268 tests across 38 files, including 6 compound/blob fixture and bounds tests. Swift/TS/Rust reproduce `walk-open-read-clunk-v1.json` and `blake3-handle-v1.json` byte-for-byte.
- iOS: full `xcodebuild test` passed; 441 tests, 1 skipped, 0 failures, including 6 `ResourceCompoundCodecTests`.
- Android: `testDebugUnitTest lintDebug assembleDebug` passed; 114 tests, 0 failures, including 7 `ResourceCompoundCodecTest` tests. Kotlin decodes and re-encodes semantically; the raw ResourceRpc fixture buffers use no file identifier.
- Rust: `cargo test` passed; 18 tests, 0 failures, including compound request, inline result, BLAKE3 blob result, read result and bounds validation.
- Compound validation is shared across languages: at most 32 path segments, 255 UTF-8 bytes per segment, no empty/`.`/`..`/`/`; inline data cap 64 KiB; blob handle version 1, BLAKE3 only, 32-byte digest, nonzero length; inline data plus blob is rejected as ambiguous.
- FlatBuffers struct bug found during Kotlin verification: `Qid` must be created after `start*` and added immediately via `addQid`; creating it before `start*` fails with `struct must be serialized inline`. Fixed in compound result, stat, attach result and open result writers.
- GitHub Actions: Protocol, Android, DesktopShell and iOS passed for the combined change. iOS failed twice with exit code 65 and passed on rerun of the same tests; the workflow now supports `workflow_dispatch` and annotates filtered failure lines for faster triage. Android's first CI run passed.

### P1-05/P1-06 verification evidence

- iOS: full `xcodebuild test` passed; 447 tests, 1 skipped, 0 failures, including 5 `RemoteRuntimeProviderTests` and lifecycle placement-diagnostic coverage.
- Web: `npm run check` passed; 269 tests across 38 files, including explicit device/runtime filtering without a placement scope.
- `RemoteRuntimeProvider` maps create/start/suspend/checkpoint/resume/stop/destroy/status; transport disconnect preserves the last observed state while marking the provider unavailable/open; authorization failures mark the provider restricted/degraded; protocol failures are typed.
- Remote runtime providers are not registered by `RuntimeRegistry.standard()`. Explicit registration plus explicit device placement is required.
- `RuntimeRegistry` emits deterministic placement diagnostics with device mismatch, pinned-world, availability, world, architecture, capability, quota and synchronization outcomes. Local providers inherit `hostDeviceId` for explicit device selection.
- `ApplicationLifecycleController.selection(for:)` retains the latest rationale and diagnostics for each started instance.
- Android, Rust and protocol assets were unchanged by P1-05/P1-06; their last full gates remain green at `d2962cd`.

### P1-07 verification evidence

- iOS: full `xcodebuild test` passed; 455 tests, 1 skipped, 0 failures, including 8 `CapabilityScopedTerminalTests`.
- `CapabilityScopedTerminal` requires a matching `airdesk://pty/spawn` lease before constructing or starting the SSH transport. Capability URI, workspace, application, requester device, session, operation and expiry are checked; active leases are single-owner.
- Denied, revoked, expired and busy leases fail with typed `CapabilityTerminalError` values and produce bounded `CapabilityLeaseAuditEvent` records. Revocation or expiry during an active session stops the transport and emits an exit event.
- `SessionCoordinator` now starts remote terminals only through `CapabilityScopedTerminal`. The terminal profile alone cannot authorize a connection; an explicit session authorization in Remote Terminal settings issues an eight-hour scoped lease. Profile changes, disconnects and runtime stops revoke the lease.
- Web: `npm run check` passed; 269 tests across 38 files. P1-07 made no web changes.
- Android, Rust and protocol assets were unchanged by P1-07; their last full gates remain green.

### P2-01 verification evidence

- Contract/fixture: `protocol/fixtures/device-agent/contract-v1.json` freezes identity, seven capability descriptors, platform permission states, request/release cases, subscription event types, lifecycle states, health counts and typed error codes.
- Shared behavior: identity projection, capability listing, authorization/availability independence, lease issuance/release, subscription delivery, health generation/counts and disconnect revocation are exercised from the same fixture in Swift, TypeScript and Kotlin.
- Typed failures covered: `capability-unknown`, `authorization-denied`, `authorization-revoked`, `capability-busy`, `capability-restricted`, `capability-unavailable`, `operation-not-allowed`, `platform-permission-denied`, `lease-not-found`, `invalid-event-type` and `agent-unavailable`.
- iOS: full `xcodebuild test` passed; 459 tests, 1 skipped, 0 failures, including 4 `DeviceAgentTests`.
- Web: `npm run check` passed; 273 tests across 39 files, including 4 `device-agent.test.ts` cases.
- Android: `testDebugUnitTest lintDebug assembleDebug` passed; 118 tests, 0 failures, including 4 `DeviceAgentTest` cases.
- Rust, protocol schema and generated bindings were unchanged by P2-01.

### P2-02 verification evidence

- `CameraCaptureStreamController` starts only after `DeviceAgent.requestCapability` grants a `capture` lease for `airdesk://media/camera/capture`; it releases that lease on stop, cancel, source failure, revocation and expiry, and rechecks lease activity and expiry for every frame.
- The controller subscribes to DeviceAgent lease events and fails closed with typed `CameraCaptureError` values for revocation, expiry, platform permission denial, restricted access, unavailable hardware, busy/restricted capabilities and cancellation.
- Frames are delivered through a bounded `CameraFrameStream`; when the consumer falls behind, newest frames are dropped and counted instead of growing memory. Stop, cancel and failure discard buffered frames. Metrics record received, admitted, dropped, oversized and total bytes.
- `AVFoundationCameraCaptureSource` checks AVFoundation authorization and hardware, requests 1280x720 BGRA at up to 30 fps, discards late video frames, applies a 4 MiB per-frame cap, and exposes only a mockable source protocol to tests.
- iOS: full `xcodebuild test` passed; 468 tests, 1 skipped, 0 failures, including 9 `CameraCaptureStreamControllerTests`.
- Camera frames remain local BGRA `Data`; encoding, remote transport, UI wiring and physical-camera qualification are not claimed by P2-02.
- Web, Android, Rust and protocol schema/generated bindings were unchanged by P2-02; their last full gates remain green at `8c522eb`.

### P2-03 verification evidence

- `ResourceRoot` supports app-scoped app Documents roots and explicit user-selected roots, rejects `/` and other non-confined app roots, requires an existing directory, resolves symlinks, and brackets user-selected access with security-scoped resource calls.
- `ResourceTransferService` confines every operation to a validated root. It rejects absolute paths, `..`, empty segments, NUL bytes, oversized paths/segments and resolved symlink escapes, while allowing symlinks that remain inside the root.
- `stat`, chunked `read` and `write` are bounded to 64 KiB per operation and a 64 MiB resulting file, validate offsets, require regular files for reads/writes and support append without leaving the root confinement model.
- Transfer events are bounded to 128 retained entries with monotonic sequence, outcome, path, byte count and offset; denied and failed operations are recorded and `onEvent` receives every event even after retention starts evicting old entries.
- The app target explicitly compiles the Swift files under `AirDesk/Resources` while continuing to exclude the bundled web desktop assets and other resource-only files.
- iOS: full `xcodebuild test` passed; 478 tests, 1 skipped, 0 failures, including 10 `ResourceTransferServiceTests`.
- Device-wide filesystem access, UI document-picker wiring, remote resource RPC/encoding and physical file-provider qualification are not claimed by P2-03.
- Web, Android, Rust and protocol schema/generated bindings were unchanged by P2-03; their last full gates remain at `8c522eb`.

### P2-05 verification evidence

- The Android capability catalog now advertises the canonical `airdesk://fs/documents/read` and `airdesk://fs/documents/write` URIs and no longer advertises the legacy `airdesk://fs/read`.
- Both document capabilities are app-scoped and user-mediated: `scope=app-documents`, `userSelectedOnly=true`, `deviceWideAccess=false` and `remoteTransfer=false`. They remain restricted and ungranted; no device-wide filesystem, file transfer or grant issuance is claimed.
- Camera availability now depends only on hardware presence and is not collapsed to `restricted` when the Android platform permission is absent. Permission state remains separate from capability authorization, which is never auto-granted by the catalog.
- The `DeviceAgent` constructor label was aligned with the shared fixture test, restoring Android test compilation for the existing contract suite.
- Android: `testDebugUnitTest` passed; 119 tests, 0 failures, then `lintDebug assembleDebug` passed.
- The shared DeviceAgent contract fixture was unchanged. ADR-012 grant/lease issuance and remote invocation enforcement remain P2-04 work and are not claimed by P2-05.
- iOS, Web, Rust and protocol schema/generated bindings were unchanged by P2-05; their last full gates remain green, including the iOS 491-test run at `097c85b`.

### P2-07 verification evidence

- `AndroidWorkspaceHost` attaches the native bridge before navigation and loads the bundled DesktopShell from the existing `WebViewAssetLoader` origin. `WebViewCompat.addWebMessageListener` restricts the object to `https://appassets.androidplatform.net`, and the document-start bootstrap exposes WebKit-compatible `airdesk` and `airdeskTerminal` handlers without modifying bundled DesktopShell JavaScript.
- `AndroidDesktopBridge` validates version 1 runtime messages and terminal actions, session identity, stale generation, sequence, viewport bounds, field lengths and terminal base64/resize bounds before dispatch. Rejections surface reason codes in diagnostics without storing terminal input or payload contents.
- `DisplaySessionController` owns a stable session identity across reloads and reconnects; generation advances for each page load. It tracks connecting/ready/degraded/failed/stopped phases, viewport, runtime state, terminal status and bridge rejections. The Presentation tab renders these diagnostics truthfully.
- The DesktopShell terminal bridge is transport-complete but has no SSH backend in P2-07. If the terminal requests a start without a P2-09 handler, it receives a truthful `terminalExit` that the Android SSH backend is unavailable; `AIRDESK_REMOTE_TERMINAL` remains disabled. P2-09 owns the foreground SSH service.
- Android: `testDebugUnitTest` passed; 136 tests, 0 failures, including 9 `AndroidDesktopBridgeTest` and 8 `DisplaySessionControllerTest` cases, then `lintDebug assembleDebug` passed.
- No physical-device WebView interaction, terminal process survival or Android MediaProjection/MediaCodec behavior is claimed. `DisplaySessionController` is the handoff point for P2-08.
- iOS, Web, Rust and protocol schema/generated bindings were unchanged by P2-07; their last full gates remain green, including the iOS 505-test run at `93550ff`.

### P2-08 verification evidence

- `AndroidVideoCapabilities` inspects `MediaCodecList.REGULAR_CODECS` encoders that advertise `COLOR_FormatSurface`, separates hardware from software encoders, and records the exact codec name. AV1 remains detectable but is never selected.
- `AndroidCodecSelector` prefers hardware HEVC, falls back to hardware H.264 when HEVC is unavailable, and can use software fallback only when explicitly enabled. An H.264 preference is not silently upgraded to HEVC, and unsupported requests fail with `CODEC_UNSUPPORTED`.
- `AndroidMediaCodecStream` configures a surface-input MediaCodec, registers a `MediaProjection.Callback`, creates an auto-mirror `VirtualDisplay`, and drains asynchronous encoder output into owned frame bytes with codec configuration. Frames carry sequence, timestamp, dimensions, codec, keyframe state and byte payload; metrics count encoded frames, keyframes and bytes.
- Configuration and capture dimensions are validated before the pipeline starts. Typed `AndroidDisplayException` codes cover invalid configuration/size, already-running state, unsupported codec, encoder creation/configuration/failure, unavailable or stopped projection, and virtual-display failure. Stop and failure release the virtual display, projection callback, input surface, codec and encoder thread.
- `DisplaySessionController` now registers display starting/running/metrics/stopped/failed snapshots alongside the desktop session. Display failures are retained when a later stop arrives, and the Presentation tab renders the selected codec, hardware/software and fallback state, dimensions, encoded frames and display error.
- Android: `testDebugUnitTest` passed; 149 tests, 0 failures, including 10 `AndroidMediaCodecStreamTest` and 11 `DisplaySessionControllerTest` cases, then `lintDebug assembleDebug` passed.
- MediaProjection consent UI, a persistent foreground capture service, physical codec behavior, zero-copy, glass-to-glass latency and hardware qualification are not claimed by P2-08.
- iOS, Web, Rust and protocol schema/generated bindings were unchanged by P2-08; their last full gates remain green, including the iOS 505-test run at `93550ff`.

### P2-09 verification evidence

- `RemoteSSHProfile`/`RemoteSSHLease` mirror the iOS terminal contract: OpenSSH host-key pinning, validated connection/size fields, `airdesk://pty/spawn`, connect/write/resize operations, single-owner leases, expiry/revocation/busy errors and bounded audit records. The lease registry is synchronized for Android's background write/event threads.
- `RemoteSSHController` runs connection setup off the caller thread, emits `ready` before reader data, chunks host output to 64 KiB, serializes write/resize, closes the transport on stop and reports transport closure once without flooding late events.
- `JschRemoteSSHTransport` uses `com.github.mwiede:jsch:0.2.21`, enforces the pinned host key through a custom `HostKeyRepository`, allocates a PTY for both shell and startup-command `exec` channels, and maps host-key, authentication, connect and channel failures to typed errors. The packaging block excludes duplicate OSGi manifests from JSch/Bouncy Castle.
- `RemoteSSHTerminal` gates every connect/write/resize through the shared lease path and audits allowed/denied/revoked/expired/busy decisions. `RemoteSSHServiceController` keeps the session alive when a client detaches, lets a newly attached client take over writes, and exposes the same `ready`/`data`/`exit` event protocol used by iOS.
- `AndroidSSHService` is a `remoteMessaging` foreground service with a low-importance ongoing notification, `START_STICKY`, `stopWithTask=false`, a local binder and truthful status. The Presentation tab binds to it, supplies a memory-only SSH profile, grants an explicit eight-hour scoped lease, and bridges terminal start/write/resize/stop plus base64 output. Reopening Terminal reattaches to a running service instead of reconnecting.
- `AIRDESK_REMOTE_TERMINAL` and `terminalConfig` are now driven by the saved profile so the bundled DesktopShell selects the SSH path; passwords are never persisted.
- Android: `testDebugUnitTest --rerun-tasks` passed; 159 tests, 0 failures, including 10 `RemoteSSHTest` cases, then `lintDebug assembleDebug` passed.
- Physical foreground-service process survival, notification permission behavior, real SSH-server interoperability, second physical-device handoff and service restoration after process kill are not claimed. Credentials are intentionally memory-only, so a killed process cannot restart SSH without user re-entry.
- iOS, Web, Rust and protocol schema/generated bindings were unchanged by P2-09; their last full gates remain green, including the iOS 505-test run at `93550ff`.

### P2-10 verification evidence

- `protocol/abi/wit/airdesk-host-abi.wit` defines package `airdesk:host-abi@0.2.0` and world `capability-host`, importing `wasi:io/streams@0.2.0`; the pinned WASI 0.2 I/O dependency package is vendored under `protocol/abi/wit/deps/io`.
- `vfs-service` exposes `mount-capability` and a confined `node` resource with stat/open-at/read-stream/write-stream/readdir/close, relative-path and no-symlink-follow rules, and typed `abi-error` results.
- `pty-service` exposes `spawn` and a lease-bound `pty-session` stdin/stdout/resize/terminate/wait/credits resource. The frozen credit contract is 262144 bytes maximum in flight, 131072 bytes resume threshold and 65536-byte maximum chunk, with no silent output drop.
- `display-sink` exposes `register-sink` and presentation-state read/update/close for AD-DISPLAY/ADR-014, guarded by `OriginPolicy` and `lease-epoch`. It has no frame, surface, pixel or submit operation; display input subscription remains outside the native capability host.
- `capability-grant` carries the COSE_Sign1 token and `lease-context`. The ABI requires token/claim/expiry/revocation/platform-permission revalidation on every host call, including through lease-bound stream handles, with typed lease, path-escape and flow-control errors.
- `protocol/fixtures/host-abi/wit-v1.json` freezes the 0.2 package/world, interfaces, error codes, lease rules, PTY credits, no-frame rule, per-runtime qualification and separate-0.3 policy.
- `protocol/abi/check.sh` resolved the WIT package with `wasm-tools` 1.263.0, validated required interfaces/functions/error codes, rejected 0.2 `stream<T>`/`future<T>` and any display frame/surface operation, checked the fixed credit values and verified the fixture. The 0.3 branch requires a separate package using `stream<T>`/`future<T>` with no `wasi:io` import.
- This is a WIT and tooling gate only. No Wanix, Rust or Swift runtime implementation, cross-runtime conformance run, lease-enforcement integration or WASI 0.3 world is claimed; those remain qualification work under ADR-018 and P2-11.

### P2-11 verification evidence

- `protocol/abi/wit/airdesk-host-abi-0_3.wit` is a separate `airdesk:host-abi@0.3.0` package and `capability-host-0-3` world. It uses `async func`, `stream<T>` and `future<T>` for VFS read/write/directory streams and PTY stdin/stdout, with the 0.3 write-direction flip and terminal futures.
- The 0.3 package has no `wasi:io` import and no reference to the 0.2 package. The 0.2 resolver runs from an isolated package directory so sibling 0.3 files cannot be merged into the 0.2 world; `check.sh` rejects mixed worlds, 0.3 `wasi:io`, and any display frame/surface operation.
- `protocol/abi/conformance/check.sh` runs the static ABI gate and validates `manifest.json` with Python. It requires per-runtime qualification, forbids assumed cross-runtime equivalence, requires evidence for passed/failed results and requires `qualifiedRuntimes` to exactly match passed runtimes.
- The manifest records `wanix`, `native-rust` and `native-swift` as `not-run` with no evidence and an empty `qualifiedRuntimes` list. No runtime conformance, execution, lease enforcement or WASI 0.3 world support is claimed.
- Verified on macOS and Linux with `wasm-tools` 1.263.0: both `protocol/abi/check.sh` and `protocol/abi/conformance/check.sh` passed. CI protocol workflow installs the pinned Linux binary and runs both checks.

### P5-01 verification evidence

- ADR-025 selects in-app ReplayKit `RPScreenRecorder` capture of AirDesk-owned workspace surfaces as the first iOS host-capture path; capture, encoder ownership, capability checks and transport stay in one process and authority boundary.
- Whole-device iOS capture through a Broadcast Upload Extension is deferred and requires a separate target, IPC/transport, shared-container/keychain and suspension decision. No other-app, system-UI or protected-content capture is claimed.
- `ScreenCaptureKit` remains prohibited on the iOS target and requires a separate macOS host target under ADR-006. External host processes remain a separate backend.
- P5-02 must introduce a mockable `DisplayCaptureSource`, keep ReplayKit/VideoToolbox work off the main thread, use a bounded encoder queue with drop-and-keyframe recovery, prefer HEVC with H.264 fallback, and make no zero-copy, AV1, glass-to-glass or hardware-qualification claim without measurement.
- P5-01 added no Xcode target, capture source, Info.plist permission or `project.yml` change; it records the platform decision only.

### P5-02 verification evidence

- `DisplayCaptureSource` is the mockable capture boundary. `ReplayKitDisplayCaptureSource` uses in-app `RPScreenRecorder.startCapture`, disables audio and forwards video `CMSampleBuffer` pixel buffers without a pre-encode frame-data copy.
- `ScreenCapturePipeline` lazily creates the encoder from the first frame and bounds in-flight frames to a configurable 1–8 (default 3). A full queue drops the new frame, records the drop and forces a recovery keyframe without blocking or growing a backlog.
- The pipeline exposes typed lifecycle/failure errors, selected codec, received/encoded/dropped/keyframe/byte/in-flight metrics, and releases the encoder and capture source on stop and failure.
- `VideoToolboxEncoder` requires hardware acceleration, configures real-time/no-reordering HEVC or H.264, forces the first and periodic keyframes, and copies compressed block-buffer bytes into owned `Data` before delivery. No zero-copy claim is made.
- HEVC is preferred with H.264 fallback. AV1 capability is detected but AV1 is never selected for encoding while it remains research-only.
- iOS: full `xcodebuild test` passed; 491 tests, 1 skipped, 0 failures, including 13 `ScreenCapturePipelineTests`.
- `DisplayCoordinator`, transport/UI wiring, pacing and Android `AndroidMediaCodecStream.kt` were not changed by this iOS host-path task. Physical ReplayKit capture, hardware codec qualification, glass-to-glass latency and zero-copy behavior are not claimed.
- Web, Rust and protocol schema/generated bindings were unchanged by P5-02; their last full gates remain green at `8c522eb`.

### P5-03 verification evidence

- `EncodedDisplayFrame` now carries HEVC/H.264 parameter sets and the NAL unit header length extracted from the encoder format description, so an out-of-process client can reconstruct a decoder format description.
- `VideoToolboxDisplayDecoder` creates HEVC/H.264 `VTDecompressionSession` instances, copies compressed data into a `CMBlockBuffer`, submits `CMSampleBuffer`s off the main actor, and reports per-frame decode wall time, process CPU time and hardware-acceleration status. AV1 remains rejected/detection-only.
- `DisplayClientPipeline` bounds decode in-flight frames, drops frames before the first keyframe and under decode backpressure, fails closed with typed errors, and records received/dropped/decoded/failure/in-flight, average/peak decode latency and CPU time.
- `DisplayFramePacer` enforces the target presentation interval, bounds the presentation queue (default 2 frames, 250 ms maximum age), drops overflow and expired frames, and records presented/dropped/overflow/late/queue-depth/queue-delay diagnostics. `DisplayFramePacingDriver` drives presentation with `CADisplayLink` at the display refresh rate capped by the configured target.
- iOS: full `xcodebuild test` passed; 505 tests, 1 skipped, 0 failures, including 14 `DisplayClientPipelineTests` and the existing 13 `ScreenCapturePipelineTests`.
- `DesktopSurface`, `DisplayCoordinator`, transport/UI wiring, the web endpoint frame path and Android MediaCodec were not changed. Physical display qualification, hardware-decode qualification, glass-to-glass or input-to-photon latency and zero-copy behavior are not claimed.
- CPU metrics are process-level wall-clock deltas around decode submission/output, not per-core, thermal or battery qualification.

### P5-04 verification evidence

- ADR-026 records `core/airdeskd` as an isolated standalone daemon carve-out from ADR-024. SSH, local PTY and process spawning remain outside the shared core and FFI/WASM boundaries.
- `protocol/airdesk.fbs` adds `TerminalMessageType`, `TerminalMessage` and additive `FabricPayload.TerminalMessage`; the v1 `MessagePayload` union is unchanged. Swift, TypeScript, Rust and Kotlin bindings were regenerated and `./protocol/check.sh` passed.
- `airdeskd` opens a real Unix `openpty`/`fork`/`execvp` PTY, reads raw bytes into a sequence-numbered bounded replay buffer, fans out to multiple attached clients, resizes with `TIOCSWINSZ`, and sends SIGHUP on close. The first transport binding is a local Unix socket with a 4-byte length prefix and a 1 MiB frame cap.
- The default replay budget is 256 KiB or 4096 chunks; reads are capped at 8 KiB. Truncation is reported to clients instead of silently claiming zero lost bytes.
- The initial lease capability is `airdesk://pty/spawn`. Attach, write, resize and detach require a live local lease; revocation and expiry are enforced, and attach authorization precedes replay/client allocation. Lease issuance, distribution and invocation enforcement remain ADR-012 work.
- Rust: `cargo test --offline` in `core/airdeskd` passed 8 tests covering frame round-trip, bounded replay/truncation, multi-client attach, reconnect sequence, lease denial/revocation/expiry, operation authorization, Unix-socket framing and a real `/bin/sh` PTY byte tee.
- Swift: `PersistentTerminalFabric` implements ADFP terminal encode/decode, length-prefixed stream framing and duplicate/sequence replay tracking. Full `xcodebuild test` passed; 547 tests, 1 skipped, 0 failures, including 4 `PersistentTerminalFabricTests`.
- Web: full `npm run check` passed; 283 tests across 40 files. Android: `testDebugUnitTest lintDebug assembleDebug` passed with 166 tests and 0 failures after regenerated Kotlin bindings were synced.
- No SSH, Iroh, WebSocket or local-forward transport is deployed for `airdeskd`; the Swift client is not yet wired to `SSHPTYSession`/`RemoteTerminalController`. Live-network process survival, deployed second-device handoff and zero-lost-byte claims remain transport/hardware-gated work.

### P5-05 verification evidence

- `TerminalCommandTimeline` consumes `OSC133Parser` events into sequence-ranged `TerminalCommandRecord`s with prompt, input, running and finished phases, exit codes and a 64-record bound. This is the native command-record half; web semantic command blocks are recorded under P4-08.
- `PersistentTerminalSession` attaches only after an acknowledgement, resumes replay from the last acknowledged sequence, deduplicates repeated chunks and detects truncated replay gaps. Stale, ahead-of-received and wrong-session acknowledgements fail closed.
- Replay emits `.command` events separately from `.data`, so rebuilding command records on reconnect does not synthesize or duplicate terminal bytes and cannot corrupt a running TUI's byte stream.
- Independent client cursors are tracked per session object, and reconnecting preserves the active command record across attach.
- Swift: full `xcodebuild test` passed; 554 tests, 1 skipped, 0 failures, including 7 `RemoteSSHReattachTests` covering phases/exit codes, attach-after-ack replay, independent clients, truncated gaps, command/byte separation and wrong-session rejection.
- No SSH/Iroh/WebSocket transport is wired to `PersistentTerminalSession`, and no controller or web bridge consumes it yet. Live second-device handoff, physical-device qualification and zero-lost-byte claims over a deployed transport remain gated.

### P3-01 verification evidence

- Added the additive `core/` Cargo workspace with `airdesk-core`, `airdesk-protocol`, `airdesk-ffi` and `airdesk-wasm`, plus `core/rust-toolchain.toml` pinning Rust 1.98.1 and `core/Cargo.lock`.
- `airdesk-core` exposes the versioned ABI smoke surface; `airdesk-protocol` exposes the current `ADEN`/v1/1 MiB compatibility check; `airdesk-ffi` re-exports the typed boundary; `airdesk-wasm` exposes only the browser-safe subset.
- The existing `core/airdeskd` daemon remains an excluded, standalone workspace under the ADR-026 carve-out. No existing codec, Swift, TypeScript, Kotlin or production crate code was moved or deleted.
- Added `.github/workflows/core.yml` for format, clippy, workspace tests and the separate daemon tests.
- `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace --locked` and `cargo test --manifest-path core/airdeskd/Cargo.toml --locked` pass. The core workspace has 6 tests; `airdeskd` retains 8.
- Decision recorded: ADR-024 is accepted for the full shared-core boundary, but every fixture-equality, platform, rollback and cutover gate remains in force.

### P4-07 verification evidence

- ADR-027 records the decision to retain WTerm plus the `@wterm/ghostty` WASM core. `docs/research/terminal-engine-benchmark-2026-11-12.md` records the method and measurements.
- Current production payload is 355,162 B JS + 13,537 B CSS + 597,635 B WASM; the committed WASM hash is `d8f93f5e38550958f459b34db9c4680bb4a935161a7a75a999d18e392b3c98d8`.
- The existing two-core conformance suite passes 12 tests covering clusters, alternate screen, scrollback, terminal modes, SGR/true color and resize. WTerm exposes DOM-native selection and accessibility; the Ghostty core retains the 5,000-line scrollback gate without discard.
- `libghostty-vt` 0.6.3 was inspected from its npm tarball: Bun/native FFI (`bun:ffi`, `dlopen`, `JSCallback`), no browser/WASM export, no iOS or darwin-x64 prebuild, no DOM selection/accessibility layer, 6.59 MB tarball and 19.08 MB unpacked, and no Apache-2.0 binding `LICENSE` file in the tarball. It is rejected as a browser replacement.
- No dependency, renderer or `TerminalBridge` behavior changed. P4-10 is unblocked without an engine migration.

### P4-08 verification evidence

- New `SemanticTerminalModel` parses OSC 133 prompt (`A`), input (`B`), running (`C`) and finished (`D;exit`) markers with BEL and `ESC \` terminators, including controls split across terminal chunks. Command text and output are tracked separately and bounded to 64 KiB per block with a 200-block history.
- Each block exposes a success/failure/running/pending/interrupted exit aura. `copyBlockOutput` strips ANSI/OSC controls, and `formatBlockMarkdown` emits fenced command/output markdown with a dynamic fence length.
- Unconfirmed local keystrokes and pastes are counted but never promoted into command blocks; command text is accepted only from shell-integration-confirmed terminal output. Copy and Markdown actions stay disabled until the shell confirms the block, and Ctrl-C marks an active block interrupted. There is no automatic retry path.
- `WTermEngine` feeds received terminal bytes through the model and can mount an accessible command-block panel with copy and Markdown controls. The DesktopShell live Wanix and SSH WTerm mounts enable the panel; `window.AirDeskWTerm.semantic` exposes model/copy/markdown helpers.
- Web: full `npm run check` passed; 290 tests across 42 files, including 5 `semantic-blocks.test.ts` and 2 jsdom `semantic-block-panel.test.ts` cases. Committed DesktopShell terminal bundles were rebuilt and pass `build:check`.
- `TerminalBridge` protocol actions were not changed; semantic blocks are web-local and no native command execution, retry or secret export was added. Physical-device and shell-integration coverage beyond OSC 133 are not claimed.

### P4-09 verification evidence

- New `AgentSupervisionModel` derives offline/idle/working/waiting/blocked/failed badges from OSC 133 command blocks and exposes read-only snapshots containing confirmed output only: prompts, unconfirmed input and command text are omitted, snapshot blocks are bounded, and credential-like text, private keys, URL userinfo and bearer tokens are redacted.
- `WTermEngine` observes semantic output, publishes agent snapshots, mounts an accessible live-region badge, disconnects it on destroy and exposes `agentSnapshot`/`agentControl`. Write/inject is denied unless an explicit `airdesk://agent/input` capability, non-empty lease, unexpired timestamp and granted action are supplied; control payloads are size/control-character checked, accepted input is audited without storing payload bytes and denied actions are audited too.
- Desktop windows gained an optional text/tone badge in window chrome. The DesktopShell Wanix and SSH terminals enable the agent badge alongside semantic blocks.
- `ApplicationLifecycleController` now derives native supervision badges from observed runtime state and provides capability/lease/action authorization plus bounded accepted/rejected audit events for write/inject, without persisting payloads. There is still no native agent input bridge or remote invocation transport.
- Web: full `npm run check` passed; 298 tests across 44 files, including 5 `agent-supervision.test.ts`, 2 jsdom `agent-badge.test.ts` and a window-manager badge case. Committed DesktopShell bundles were rebuilt and pass `build:check`.
- iOS: full `xcodebuild test` passed; 556 tests, 1 skipped, 0 failures, including 2 `ApplicationLifecycleControllerTests` agent cases.
- P4-09 is code-level: there is no live external agent, no WebMCP dependency and no remote agent transport. Read-only snapshots cannot execute commands, and write/inject is inert unless a caller supplies an explicit live grant.

### P4-10 verification evidence

- WinBox movement now writes `--airdesk-window-x`/`--airdesk-window-y` and the committed `.airdesk-window` rule pins `left`/`top` to zero, applies `translate3d(...)`, and marks `will-change: transform`. WinBox still owns its internal position, drag, resize and focus mechanics, while visual movement is a compositor transform rather than layout of `left`/`top`.
- Window bodies use `contain: content` and isolation, while WinBox's existing `contain: strict` remains on `.wb-body`; terminal and window content cannot escape their layout/paint boundary.
- `WTermEngine.setRenderingPaused` delegates to the WTerm renderer. The DesktopShell pauses the Wanix and SSH WTerm pane on window blur or minimize, resumes it on focus, and applies the latest state after asynchronous engine creation.
- New `tiling.ts` provides deterministic BSP layout (split on the longer axis, count-proportional halves, configurable gaps) and ribbon layout (main pane plus overflow ribbon on the left, right, top or bottom). `WinBoxWindowManager.tile()` applies either layout to the current visible focus order and returns the computed bounds.
- Web: full `npm run check` passed; 306 tests across 46 files, including 5 `tiling.test.ts`, 8 window-manager cases with transform and layout assertions, and a paused-renderer engine test. Committed window-manager, terminal and preview bundles were rebuilt and pass `build:check`.
- iOS: full `xcodebuild test` passed; 556 tests, 1 skipped, 0 failures. The desktop-shell bridge drag test now reads the transform offsets instead of `offsetLeft`/`offsetTop`.
- P4-10 is a web/desktop-shell rendering change. It does not implement P4-12 window sling and does not claim physical GPU frame-time or hardware-display qualification.

### P4-12 verification evidence

- New `WindowProjectionRegistry` exists in TypeScript, Swift and Kotlin with the same identity and lifecycle contract: `windowId`, `workspaceId`, `hostSessionId`, generation, target kind `cast|browser|android`, surface revision and host-only compute location.
- `begin` rejects duplicate windows and target conflicts; `acknowledgeSurface` rejects stale revisions; `disconnect` preserves identity and surface revision; `resume` rejects stale generations, restores window identity and can switch target; `release` clears the record for reuse. `CastSessionCoordinator` publishes `projectedWindows` and exposes the lifecycle methods.
- The Android presentation screen renders the current projected-window state, title, surface revision and compute location.
- Web: full `npm run check` passed; 311 tests across 47 files, including 5 `remote-window-projection.test.ts` cases.
- iOS: full `xcodebuild test` passed; 573 tests, 1 skipped, 0 failures, including 5 `WindowProjectionTests` cases and a fake Cast adapter lifecycle test.
- Android: `testDebugUnitTest lintDebug assembleDebug` passed; 171 unit tests, including 5 `WindowProjectionTest` cases.
- P4-12 currently projects identity and surface state; it does not transport window pixels to a live Cast/browser/Android receiver. Physical Cast/browser/display qualification, real target rendering and hardware display gates remain unclaimed.

### P4-06 verification evidence

- `OnboardingQuickConnect` deterministically recommends an external display, active AirPlay mirroring, the first available Cast receiver, or the on-device preview. The welcome screen starts the recommended route directly and no longer requires the display/setup screens for the default path.
- The previous manual selector remains reachable as `Advanced display setup`, is labelled as advanced in `ConnectionView`, and still exposes AirPlay, Cast, external-display and preview choices.
- The quick-start action checks the selected runtime entitlement before starting and presents Pro access instead of bypassing the runtime lock. Cast discovery runs while the welcome screen is visible.
- Accessibility labels and hints describe the recommended destination, the immediate start behavior and the advanced fallback.
- iOS: full `xcodebuild test` passed; 578 tests, 1 skipped, 0 failures, including 5 `OnboardingQuickConnectTests` cases for priority, availability, fallback and accessibility copy.
- P4-06 does not claim UWB/Bonjour proximity qualification or automatic proximity pairing; P4-05 remains research/hardware-gated.

### P4-04 verification evidence

- New `SessionContinuityModel` derives a compact presentation for connecting, ready, recovering and failed states. The ready pill shows the selected direct/relay path, RTT or measured input latency, the runtime capability summary and a persistent migration note when the selected path changes.
- `SessionCoordinator` publishes `sessionContinuity`, observes `IrohFabricPeer.paths` through `AppEnvironment`, refreshes measured latency at a one-second throttle, resets migration state per session and emits haptics only on session-ready, path-upgrade, path-degrade, recovery and failure transitions. The duplicate ready/error haptics in `performConnection` and `performRecovery` were removed.
- `SessionContinuityPill` is a non-blocking top overlay with accessibility labels. `RootView` presents `SessionRecoveryView` only after automatic recovery was attempted; initial connection failures return to onboarding with the error pill instead of a blocking recovery screen.
- iOS: full `xcodebuild test` passed; 568 tests, 1 skipped, 0 failures, including 12 `SessionContinuityTests` covering idle, connecting, direct/relay path, measured latency, capability summary, relay/direct and same-transport path migration, stable-path haptic suppression, recovery and failure.
- Web: full `npm run check` remains green at 306 tests across 46 files; no web source changed.
- P4-04 uses current selected-path diagnostics only. It does not claim live Wi-Fi/cellular roaming, multipath, relay failover qualification or physical-device haptic verification.

### Research qualification decisions (2026-11-12)

- P1-09: a self-built Iroh 1.4 FFI path may be evaluated only if the existing Swift/Kotlin language targets exist and the normal loopback, relay, roaming and rollback evidence is produced. The product pins remain 1.2.0 until then.
- P4-05: physical UWB distance/angle tests, privacy/threat review and false-positive limits are required before proximity claims. Bonjour and manual pairing remain the fallback.
- P4-11: no Loro/CRDT decision until P3-03 and the shared-core fixture gates are complete.
- P3-05: a Rust SPAKE2+ path requires RFC 9383 vectors, `confirmV`-first flow, subgroup/cofactor and zeroization checks, fixture parity and independent review. No product cutover follows from passing vectors alone.
- ADR-024: user direction accepted the full shared-core boundary. Only the additive workspace scaffold exists; no native/web implementation has moved.

### Environment notes

- The local container has no `node`, `npm`, `cargo`, `swift`, `xcodebuild`, `python3`, `perl`, `sqlite3` or `adb`; it is not a verification environment.
- Mac remote: `ssh amharik@100.89.65.40`; web Node path `/Users/amharik/.local/node-v22.23.4-darwin-x64/bin:$PATH`; Cargo `/Users/amharik/.cargo/bin/cargo`.
- Android remote: `sillyoci`; existing checkout `/home/ubuntu/airdesk-android-agent/android`; sync `protocol/fixtures/adfp` to the checkout parent.
- iOS signing remains unavailable on the Mac; only simulator builds/tests and unsigned device artifacts are possible.

## 8. Hardware and live-network gates

These are not code-level tasks and must not be marked done from simulator or loopback evidence:

- Physical iPhone/iPad install, camera permission, background/foreground, thermal and battery behavior.
- Physical Android install, MediaProjection consent, MediaCodec capability, foreground service and battery.
- Cast/Chromecast/Google TV, AirPlay, USB-C/HDMI and external display matrix.
- Direct LAN, 5 GHz Wi-Fi, cellular, tailnet and relay transport measurements.
- Glass-to-glass latency, multi-controller contention and long-running PTY reattach under real network migration.
- UWB proximity pairing on supported hardware; fallback verification on unsupported devices.

## 9. Risks and kill criteria

| Risk | Mitigation / kill criterion |
| --- | --- |
| Big-bang Rust rewrite destabilizes all platforms | Stage extraction; keep native paths behind flags; stop if fixture equality or build time regresses |
| Cryptographic drift during Rust port | RFC 9383 vectors, cross-language fixtures and independent review; do not cut over on one implementation |
| Iroh 1.4.x FFI unavailable or incompatible | P1-09 verified no `1.3.x`/`1.4.x` FFI or Maven release exists; keep the 1.2.0 product pin, use the 1.2.0 path watchers/diagnostics, and do not claim live multipath/roaming until a matching release and network tests exist |
| ScreenCaptureKit is the wrong host API | Decide ReplayKit vs macOS host before writing capture code; kill zero-copy iOS claim if no viable host path |
| libghostty-vt/WebMCP APIs differ from source plan | ADR-027 rejects `libghostty-vt` for browser/iOS because it is a Bun/native FFI binding without browser, selection, accessibility or iOS support; keep the WTerm + `@wterm/ghostty` path and its integrated `renderingPaused` control. Revisit only with a browser/WASM adapter and the ADR-027 gates. |
| UWB unavailable or privacy-sensitive | Keep Bonjour/manual fallback; require threat-model review; do not make proximity mandatory |
| CRDT migration corrupts workspace | Keep current merge-class model until operation log has deterministic corpus and rollback; no workspace-wide CRDT without ADR |
| Android parity claimed without CI | Block parity claims until `android.yml` is green; no exception |
| ADR-013/014/018 promoted early | Keep `Proposed` until evidence gates; review at each phase exit |
| Hardware qualification blocks release | Ship code-level features with truthful “unqualified” diagnostics; keep Cast/hardware dev-only |

## 10. Immediate next sprint

1. P2-09 retains one physical gate: install the debug APK on an Android device, connect to a real SSH server, background the app, verify the foreground service/session survives, then verify reattach and second-device handoff. Do not mark P2-09 `Verified` from JVM tests alone.
2. P2-10 and the P2-11 static gate are complete: the 0.3 world is separate, uses `stream<T>`/`future<T>`, and the conformance manifest records every runtime as `not-run`. Runtime conformance and lease-enforcement integration remain pending; do not claim runtime qualification from the WIT check alone.
3. P2-04 now supplies native grant-chain, lease, revocation and `cnf` authorization with audit events on top of P1-02 workspace-key evidence. Production remote invocation transport wiring remains pending and must not be claimed from the standalone service tests.
4. P2-06, P4-02, P4-03, P4-08, P4-09, P4-10, P5-04 and P5-05 now supply Android packed movement/lease arbitration, the iOS display-rate local cursor with host-cursor suppression, the capability/lease-gated semantic input deck with OSC 133 state input, web OSC 133 command blocks with exit aura/copy/markdown and unconfirmed-input safety, web/native read-only agent supervision with explicit write/inject grants and payload-free audit, GPU-transform WinBox movement with BSP/ribbon tiling and paused inactive terminal panes, the persistent PTY daemon/codec with bounded ADFP replay and lease checks, and the native OSC 133 command-record replay/handoff model. P4-04, P4-07, P4-09, P4-10 and the P4-12 lifecycle model are complete at code level; P4-04 consumes the existing Iroh 1.2.0 path diagnostics, P4-12 projects identity/surface state without transporting window pixels, and P1-09 live migration/roaming remains hardware-gated. The P2-06 surface is not yet mounted over the presentation WebView; the P4-02 cursor control is a native JSON bridge message, not ADFP FlatBuffers; the P4-03 terminal phase currently comes from remote terminal output rather than the bundled shell; `airdeskd` has no deployed SSH/Iroh/WebSocket transport and its Swift client is not yet wired into `SSHPTYSession`/`RemoteTerminalController`; and no physical-device, remote-input transport or physical-display qualification is claimed.
5. P5-03 is code-level only until transport/UI wiring and physical-display qualification exist; do not claim glass-to-glass latency. P5-04 and P5-05 do not claim live-network process survival, deployed second-device handoff or zero lost bytes. P4-08 is web-local and does not claim native retry/execution or secret export. P4-09 is web/native-model code only: there is no live external agent, remote agent transport or WebMCP dependency, and write/inject remains inert without an explicit live grant.
6. Keep `milestones.md` unchanged until a task actually passes its gate.
7. P4-06 now supplies a one-tap display/route recommendation with the manual selector retained as advanced setup. P4-05 UWB proximity remains research/hardware-gated, so P4-06 does not claim proximity qualification.
8. P3-01 is complete with an accepted ADR-024 and a green additive core workspace. P3-02 is now the next extraction step: move packed/movement codecs with byte-for-byte fixture parity, keep the legacy crate as a compatibility re-export, and do not delete either path.

## 11. ADR and documentation updates

| Document | Update |
| --- | --- |
| New ADR-024 | Shared Rust core, UniFFI/C-ABI/WASM boundary, fixture ownership, cutover and rollback |
| New ADR-025 | Host capture and media pipeline platform decision |
| New ADR-026 | Standalone persistent PTY daemon carve-out, ADFP terminal attachment, replay and lease enforcement |
| ADR-010 | Additive ADFP envelope, ResourceCompound and blob handle semantics |
| ADR-011/012 | Pairing signing-key distribution and native lease/invocation enforcement |
| ADR-013 | Evidence status mechanism; stays `Proposed` until XPORT-02 |
| ADR-014 | Explicitly retain loopback-only until a non-loopback decision |
| ADR-016/017 | Operation-log sync evaluation, remote provider and placement boundaries |
| ADR-018 | WIT host ABI package and conformance gate |
| ADR-021 | Product Iroh version upgrade decision |
| `milestones.md` | Update only after tasks pass tests and review |

## 12. What this plan does not claim

- It does not claim a 100x capability gain or 1000x UX gain.
- It does not claim sub-2 ms local cursor latency, 10–30 ms LAN glass-to-glass latency, or battery/thermal targets.
- It does not claim the repository currently has a Rust core, libghostty-vt, WebMCP, UWB, zero-copy capture, CRDT workspace sync or Android parity.
- It does not authorize a public browser endpoint, relay by default, Cast production use or App Store signing.
- It does not promote any proposed ADR.

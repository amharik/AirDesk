# AirDesk 100x/1000x Masterplan — Execution Breakdown

- **Status:** Planning only — no implementation commitment and no ADR promotion
- **Date:** 2026-11-09
- **Baseline:** `dev` at `9499bf6`, plus uncommitted P1 work described below
- **Input:** User-supplied 100x product / 1000x UX masterplan
- **Related:** `milestones.md`, `docs/planning/workspace-fabric-plan.md`, `docs/planning/release-roadmap.md`, ADR-001 through ADR-023

This document maps the masterplan onto the repository as it actually exists. It is deliberately more conservative than the source plan: the 100x/1000x targets are treated as hypotheses, the Rust core is staged behind a compatibility boundary rather than rewritten in one pass, and hardware/live-network claims remain gated.

## 1. Executive recommendation

Do not execute the masterplan as a four-week big-bang Rust rewrite. Execute it as six parallel workstreams with a hard compatibility boundary:

1. Stabilize the uncommitted P1 work and add missing Android CI.
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
  - No Android CI workflow exists.

### 2.2 In-flight uncommitted work

These files were added or modified during the initial P1 implementation attempt and are not verified end to end:

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

Phase 0 must either finish, test and commit these changes or revert them. Do not build later milestones on unverified partial files.

### 2.3 Masterplan corrections and gaps

- The product pins `IrohLib` 1.2.0 in `project.yml` and `iroh-android` 1.2.0 in `android/app/build.gradle.kts`. Only `research/iroh-probe/Cargo.toml` uses `iroh = 1.4.1`. Product upgrade is a separate, gated task.
- `protocol/rust/` currently contains packed/movement codecs, not a shared core or FFI layer.
- `libghostty-vt`, OSC 133 handling, `renderingPaused`, WebMCP, one-euro filtering, UWB discovery and zero-copy media capture are not present in tracked source. ResourceCompound and BLAKE3 blob handles are now implemented but uncommitted.
- The current app target is iOS 17.5 with Mac Catalyst disabled. `ScreenCaptureKit` is a macOS API and cannot be used by the current iOS host target. The host strategy must choose ReplayKit/broadcast extension, a separate macOS host target, or an external host process before implementation.
- ADR-013 is `Proposed`; `XPORT-02` cannot be signed off without measurements.
- ADR-014 deliberately keeps the browser endpoint loopback-only. Non-loopback browser transport is an architecture decision, not a host-binding change.
- ADR-018 is still `Proposed`; a WIT package and host ABI do not exist.
- No Android CI exists, so Android parity claims currently depend on manual remote builds.
- The web terminal has `readText()` but no OSC 133 command-block model, no `renderingPaused` integration and no WebMCP authorization layer.
- Native capability descriptors exist, but there is no cross-platform `DeviceAgent` contract, no automatic workspace signing-key distribution and no native lease/invocation enforcement.

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
| P0-01 | Verify and land browser WebRTC pairing orchestration | `web/src/identity/pairing-webrtc-session.ts`, `pairing-webrtc.ts`, `index.ts`; `web/test/pairing-webrtc-session.test.ts`, `pairing-webrtc.test.ts`, `pairing-signaling.test.ts` | Full-checkout `npm run check` passes; binding mismatch rejects before SAS; malformed/duplicate/out-of-order signals covered; no live signaling server claimed | — | Verified, uncommitted |
| P0-02 | Verify or revert Android fabric/ADFP partials | `android/.../fabric/FabricTransport.kt`, `IrohFabricTransportAdapter.kt`, `protocol/AdfpFabricSession.kt`; `android/app/src/test/.../IrohFabricTransportAdapterTest.kt`, `AdfpFabricSessionTest.kt` | Remote `testDebugUnitTest`, `lintDebug`, `assembleDebug` pass; 1 MiB cap and channel routing enforced; pairing path unchanged | P0-04 | Verified, uncommitted |
| P0-03 | Verify or revert namespace partial | `AirDesk/Namespace/NamespaceImportService.swift`; `AirDeskTests/NamespaceImportServiceTests.swift` | Compiles in AirDeskTests; path/symlink/lease/fid tests pass; not wired into production | — | Verified, uncommitted |
| P0-04 | Add Android CI | `.github/workflows/android.yml`, `android/gradle.properties` if needed | JDK 17 + Android SDK 35; `testDebugUnitTest`, `lintDebug`, `assembleDebug` on push/PR paths | — | Verified, first run green |
| P0-05 | Add shared-core boundary ADR | `docs/adr/024-shared-core-and-ffi-boundary.md`, `docs/adr/README.md` | ADR is `Proposed`; defines what may move into Rust, compatibility fixtures, rollback and ownership | P0-01..03 | Proposed |
| P0-06 | Freeze Phase 1 contracts | `protocol/fixtures/**`, `docs/planning/100x-masterplan-execution.md`, `milestones.md` | ADFP envelope, remote runtime, DeviceAgent and WIT contracts have named owners and fixture paths | P0-01..05 | Contract paths frozen; ADFP and ResourceCompound/blob fixtures verified, others pending P1-05/P2-01/P2-04 |

#### Phase 1 contract freeze (P0-06)

| Contract | Owner | Fixture path(s) | Frozen shape | Consumers |
| --- | --- | --- | --- | --- |
| ADFP envelope v1 | Protocol owner | `protocol/fixtures/adfp/envelope-v1.json`, `protocol/fixtures/adfp/payloads-v1.json` | File identifier `ADEN`, envelope version `1`, 1 MiB maximum, typed header with expiry/correlation/idempotency, reliable-channel map | Swift, TypeScript, Rust, Kotlin |
| ResourceCompound and blob handles | Protocol owner | `protocol/fixtures/resource-compound/*.json`, `protocol/fixtures/resource-blob/*.json` | Additive compound Walk/Open/Read/Clunk semantics; >64 KiB results return a versioned BLAKE3 handle | Swift, TypeScript, Rust, Kotlin |
| Remote runtime lifecycle | Runtime owner | `protocol/fixtures/remote-runtime/lifecycle-v1.json` | Create/start/suspend/checkpoint/resume/stop/destroy/status, disconnect preservation and typed transport/authorization failures | Swift, TypeScript |
| DeviceAgent contract | Capabilities owner | `protocol/fixtures/device-agent/contract-v1.json` | Identity, capability descriptors, request/release, subscription, health, typed lifecycle and platform-denial results | Swift, TypeScript, Kotlin |
| Host ABI WIT | Runtime and security owners | `protocol/fixtures/host-abi/wit-v1.json` | `airdesk:host-abi@0.1.0`, WASI 0.2 baseline, VFS/PTY interfaces, per-runtime qualification, no display frame submission | Swift, Rust, Wanix, browser |
| Movement and one-euro filter | Input owner | `protocol/fixtures/input/one-euro-v1.json` | Deterministic pointer/movement normalization and filter outputs with no phase lag at high speed | Swift, TypeScript, Rust |

Compatibility rules:

- A fixture path is a contract even before its first file exists; the consuming task is blocked until the fixture and owner are present.
- A fixture change is a compatibility change and requires review from every consumer owner.
- No consumer may claim cross-language parity from a round-trip test alone; invalid, truncated, oversized and wrong-version fixtures are mandatory.
- `protocol/check.sh` verifies schema conformance and generated bindings; fixture equality is a separate CI gate owned by the protocol owner.

### Phase 1 — Trust, protocol and remote foundation (12–16 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P1-01 | Production signaling adapter and loopback harness | `web/src/identity/pairing-signaling.ts`, `pairing-webrtc-session.ts`; new signaling transport tests | Host/controller exchange real offer/answer/candidates through an injected transport; closed/malformed/duplicate signals fail typed; no plaintext secret in signaling | P0-01 | Pending |
| P1-02 | Automatic workspace signing-key distribution | `AirDesk/Sync/WorkspaceSyncKeyStore.swift`, `WorkspaceSyncRuntime.swift`, `AirDesk/Identity/PairingLiveSession.swift`; `web/src/identity/session-keys.ts`, `web/src/sync/**` | After SAS, peers derive/exchange the workspace signing key; revoked peers cannot receive or use it; cross-platform fixture passes | P0-01, P1-01 | Pending |
| P1-03 | ADFP production envelope codec | `AirDesk/Protocol/ADFPEnvelopeCodec.swift`; `AirDesk/Fabric/IrohFabricInputCodec.swift`, `IrohFabricPeer.swift`; `web/src/protocol/**`; `protocol/rust/src/**`; Android `AdfpFabricSession.kt` | Reliable channels carry validated envelopes; file id/version/size/expiry/correlation/idempotency enforced; golden fixtures match across Swift/TS/Rust/Kotlin | P0-02, P0-06 | Verified, uncommitted |
| P1-04 | ResourceCompound and blob handle protocol | `protocol/airdesk.fbs`, `protocol/baseline/airdesk_v1.fbs`, `protocol/fixtures/resource-compound/*.json`, `protocol/fixtures/resource-blob/*.json` | Additive schema; compound Walk/Open/Read/Clunk has one-RTT semantics; >64 KiB result can return BLAKE3 handle; all generated bindings and conformance pass | P1-03 | Verified, uncommitted |
| P1-05 | Remote runtime provider | `AirDesk/Runtime/RemoteRuntimeProvider.swift`, `RuntimeRegistry.swift`, `RuntimeProvider.swift`; `AirDeskTests/RemoteRuntimeProviderTests.swift` | Lifecycle maps create/start/suspend/checkpoint/resume/stop/destroy/status; disconnect preserves observed state; typed transport/authorization errors; not default-enabled | P1-03 | Pending |
| P1-06 | Placement integration and diagnostics | `AirDesk/Runtime/RuntimeRegistry.swift`, `AirDesk/Workspace/WorkspaceOrchestrator.swift`, `ApplicationLifecycleController.swift`; `web/src/remote/placement.ts` | Deterministic local/device/runtime selection; explicit device filter; typed unavailable/transport/authorization failures; diagnostics explain selection | P1-05 | Pending |
| P1-07 | Capability-scoped remote terminal | `AirDesk/Remote/CapabilityScopedTerminal.swift`, `RemoteTerminalController.swift`, `SessionCoordinator.swift`; `AirDeskTests/CapabilityScopedTerminalTests.swift` | Connect requires matching unexpired lease; denied/revoked/busy are typed and auditable; no capability bypass through terminal profile | P1-03, P1-05 | Pending |
| P1-08 | Resource RPC and scoped namespace import | `AirDesk/Protocol/ResourceRPCClient.swift`, `ResourceRPCServer.swift`, `AirDesk/Namespace/NamespaceImportService.swift`; `AirDeskTests/ResourceRPCTests.swift`, `NamespaceImportTests.swift` | All opcodes, fid lifecycle, path confinement, symlink escape, size caps and lease denial/revocation covered; no 9P2000 tunneling; chunked transfer for large payloads | P0-03, P1-04 | Pending |
| P1-09 | Iroh product upgrade spike | `project.yml`, `android/app/build.gradle.kts`, `AirDesk/Fabric/**`, `research/iroh-probe/` | Verify IrohLib/FFI 1.4.x availability; document API gaps; test path migration/roaming and relay diagnostics on loopback before product pin changes | P0-04 | Research |
| P1-10 | Transport evidence upgrade | `scripts/research/transport_bench.ts`, `run-transport.sh`, `run-iroh*.sh`, `research/scenarios/**`, `docs/research/runs/**` | `cpu_percent`, build/runtime/network/device metadata; p50/p95/p99 recorded; no claim without method | P0-04 | Partial |

### Phase 2 — Agent parity and ABI (16–22 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P2-01 | Cross-platform `DeviceAgent` contract | `AirDesk/Capabilities/DeviceAgent.swift`, `android/.../agent/DeviceAgent.kt`, `web/src/capability/**`; shared fixtures | Identity, capabilities, request/release, subscribe, health and typed lifecycle on all clients; availability and authorization remain independent | P0-06 | Pending |
| P2-02 | iOS camera capture streaming | `AirDesk/Capture/CameraCaptureSource.swift`, `CameraCaptureStreamController.swift`; tests with mock source | Explicit authorization/lease gate; bounded frames/backpressure; cancel and permission-denied typed; no physical camera required for unit tests | P2-01 | Pending |
| P2-03 | iOS document roots and file transfer | `AirDesk/Resources/ResourceRoot.swift`, `ResourceTransferService.swift`; tests | App-scoped/user-selected roots; path/symlink confinement; bounded read/write/stat; transfer events; no device-wide access | P2-01 | Pending |
| P2-04 | Native capability lease and invocation enforcement | `AirDesk/Capabilities/CapabilityLeaseManager.swift`, `CapabilityAuthorizer.swift`, `CapabilityInvocationService.swift` | Issuance/expiry/revocation; provider/root issuer checks; remote invocation denied without matching lease/`cnf`; audit event | P2-01, P1-02 | Pending |
| P2-05 | Android agent contract and canonical URIs | `android/.../agent/DeviceAgent.kt`, `capabilities/**`, `protocol/AdfpCapabilityMapper.kt` | Canonical `airdesk://fs/documents/read` plus `write`; camera authorization aligned with ADR-012; tests | P2-01 | Partial |
| P2-06 | Android precision input controller | `AndroidTrackpadSurface.kt`, `AndroidInputRouter.kt`, `InputLease*` equivalents; tests | 120 Hz local cursor path; packed movement; no stuck input; multi-controller arbitration | P2-01, P4-01 | Pending |
| P2-07 | Android workspace/terminal bridge | `AndroidWorkspaceHost.kt`, `AndroidDesktopBridge.kt`, `DisplaySessionController.kt`; tests | Bundled DesktopShell drives workspace host and terminal bridge; reconnect preserves identity; truthful diagnostics | P1-05, P2-01 | Partial |
| P2-08 | Android MediaProjection/MediaCodec stream | `AndroidMediaCodecStream.kt`, `DisplaySessionController.kt`; tests | Registered display pipeline; hardware codec capability detection; fallback and typed failure; physical qualification separate | P2-07 | Pending |
| P2-09 | Android persistent SSH service | `AndroidSSHService.kt`, `RemoteSSH*`; tests | Foreground service; reattach and second-device handoff use same protocol as iOS; process survival tested remotely | P1-07 | Pending |
| P2-10 | WIT host ABI 0.2 | `protocol/abi/wit/airdesk-host-abi.wit`, `protocol/abi/README.md`, `protocol/abi/check.sh` | `vfs-service`, `pty-service`, `display-sink`, typed errors, lease revalidation, 256 KiB PTY credits, no display frame submission | P2-01 | Pending |
| P2-11 | WIT 0.3 evaluation and conformance | `protocol/abi/wit/airdesk-host-abi-0_3.wit`, `protocol/abi/conformance/**` | Separate 0.3 world using `stream<T>`/`future<T>`; no mixed worlds; conformance harness runs where tooling exists | P2-10 | Research |

### Phase 3 — Shared Rust core extraction (20–30 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P3-01 | Create core workspace | New `core/Cargo.toml`, `core/airdesk-core/`, `core/airdesk-ffi/`, `core/airdesk-wasm/`, `core/airdesk-protocol/`; `.github/workflows/core.yml` | ADR-024 approved for implementation; crates build; no existing code deleted | P0-05 | Pending |
| P3-02 | Move low-risk codecs | `protocol/rust/src/packed.rs`, `movement.rs`, `lib.rs`; `core/airdesk-protocol/**`; fixtures | Packed/movement byte equality across Swift/TS/Rust; existing tests continue; protocol crate re-exports or compatibility shim | P3-01 | Pending |
| P3-03 | Move ADFP envelope/resource codec | New `core/airdesk-protocol/src/envelope.rs`, `resource.rs`; shared fixtures | Golden bytes and malformed-frame corpus match Swift/TS/Kotlin; Rust becomes reference but not yet sole source | P1-03, P1-04, P3-02 | Pending |
| P3-04 | Extract pairing transcript/key schedule | New `core/airdesk-pairing/**`; `protocol/fixtures/ad-pair-1.json` | AD-PAIR-1 transcript, HKDF schedule, SAS and scrypt registration match existing Swift/TS/Kotlin fixtures | P3-01 | Pending |
| P3-05 | Evaluate Rust SPAKE2+ implementation | `core/airdesk-pairing/**`; RFC 9383 vectors | `confirmV`-first, cofactor/subgroup checks, zeroization and error handling proven; no product cutover until independent review | P3-04 | Research |
| P3-06 | UniFFI Swift/Kotlin bindings | `core/airdesk-ffi/**`, `scripts/build-core-apple.sh`, `scripts/build-core-android.sh`, `project.yml`, `android/app/build.gradle.kts` | Generated bindings build in CI; app can call a non-authoritative core smoke API behind a flag | P3-02, P3-03 | Pending |
| P3-07 | WASM component target | `core/airdesk-wasm/**`, `web/src/core/**` | Deterministic wasm builds; web uses only smoke/adapter path; no TypeScript crypto removal yet | P3-03 | Pending |
| P3-08 | Feature-flagged cutover | `AirDesk/Core/**`, `web/src/core/**`, `android/.../core/**`, settings/diagnostics | Per-feature flags for movement, envelope, pairing and sync; rollback to native path; telemetry reports active path | P3-06, P3-07 | Pending |
| P3-09 | Remove duplicated implementations | Delete/replace only after equivalence and one release cycle; `README.md`, `milestones.md`, ADR updates | Duplicate code paths removed with no regressions; rollback tag retained | P3-08, P1-10 | Pending |

### Phase 4 — Input, terminal, sync and UX (14–20 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P4-01 | One-euro pointer filter | `AirDesk/Input/PointerState.swift`, `InputDispatcher.swift`, `protocol/rust/src/movement.rs`, `web/src/protocol/movement.ts`; tests | Deterministic filter fixture; no phase lag at high speed; native/web output matches | P0-06 | Pending |
| P4-02 | Decoupled local cursor and host suppression | `AirDesk/Input/AirCursorView.swift`, `MacTrackpadView.swift`, `InputDispatcher.swift`, `AirDesk/Display/**`; protocol cursor shape/hotspot | Local cursor renders at display rate; remote cursor shape/hotspot arrives out of band; no double cursor; host suppression verified | P4-01 | Pending |
| P4-03 | Semantic input deck | `AirDesk/Features/Keyboard/KeyboardBar.swift`, `MacInputDeck.swift`, `HardwareKeyboardCapture.swift`; OSC 133 state input | Context modes A/B/C/D drive bars and gestures; no modal preview dependency; all actions have capability/lease checks | P4-02 | Pending |
| P4-04 | Continuity pill and haptics | `AirDesk/Features/Session/SessionRecoveryView.swift`, `RootView`/`AppEnvironment`, `AirDesk/Design/Haptics.swift`; telemetry overlay | Non-blocking connection/latency/capability pill; path migration status; haptics only for semantic events; recovery screen removed or fallback-only | P1-05, P1-09 | Pending |
| P4-05 | Ambient proximity pairing | `AirDesk/Discovery/BonjourDiscovery.swift`, new `NearbyInteractionDiscovery.swift`; `android/.../discovery/UwbDiscovery.kt`; `web/src/identity/pairing-signaling.ts` | Bonjour and UWB proximity offer gated by distance/angle; manual code remains fallback; privacy/threat model covers proximity leakage | P0-01, P4-04 | Research |
| P4-06 | Onboarding collapse | `AirDesk/Features/Onboarding/*`, `AirDesk/Identity/PairingCoordinator.swift`, `Settings/PairingSettingsView` | Proximity/one-tap path reaches workspace without five screens; manual flow remains in advanced fallback; accessibility tests | P4-05 | Pending |
| P4-07 | Terminal engine decision and standardization | `web/src/terminal/**`, `web/package.json`, `AirDesk/Web/TerminalBridge.swift`; research ADR | Benchmark libghostty-vt/@wterm/ghostty against current engine for size, VT coverage, selection, accessibility and license; decide before replacement | P0-06 | Research |
| P4-08 | Semantic command blocks | `web/src/terminal/terminal-engine.ts`, `wterm-engine.ts`, new `semantic-blocks.ts`; `AirDesk/Web/TerminalBridge.swift` | OSC 133 blocks, exit aura, copy output, markdown view and unconfirmed-input safety; no automatic retry | P4-07 | Pending |
| P4-09 | Read-only agent supervision | `web/src/terminal/**`, `web/src/desktop/**`, `AirDesk/Workspace/ApplicationLifecycleController.swift` | Agent state badges; read-only text snapshots; write/inject requires explicit capability; no prompt/secret leakage | P4-08, P2-04 | Pending |
| P4-10 | WinBox rendering and tiling | `web/src/desktop/winbox.ts`, `window-manager.ts`, `shell-runtime.css` | GPU-transform-only movement, layout/style/paint containment, `renderingPaused` for inactive panes, BSP/ribbon layout | P4-07 | Pending |
| P4-11 | Operation-based workspace sync | `AirDesk/Sync/WorkspaceSyncMerge.swift`, `web/src/sync/merge.ts`, `protocol/airdesk.fbs`; new core sync crate | Operation log with Lamport/actor ordering; deterministic offline/multi-writer convergence; existing merge fixtures preserved or migrated with ADR | P3-03, P1-02 | Research |
| P4-12 | Window sling | `web/src/remote/placement.ts`, `AirDesk/Cast/CastSessionCoordinator.swift`, `AirDesk/Web/BrowserEndpointHost.swift`, `android/.../PresentationScreen.kt` | Window detach/project to paired Cast/browser/Android target; compute stays on host; reconnect restores window identity; hardware gate | P1-06, P4-10 | Pending |

### Phase 5 — Media, persistent PTY and qualification (12–20 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P5-01 | Host capture platform decision | New ADR-025; `AirDesk/Display/**`, `project.yml` | Decision records iOS ReplayKit/broadcast extension vs separate macOS host vs external host; ScreenCaptureKit only if a macOS target exists | P0-05 | Research |
| P5-02 | Zero-copy encoder pipeline | `AirDesk/Display/ScreenCapturePipeline.swift`, `VideoToolboxEncoder.swift`, `DisplayCoordinator.swift`; `android/.../AndroidMediaCodecStream.kt` | Capture surface -> encoder with bounded queues; HEVC/AV1 capability detection; keyframe/recovery; no unbounded memory | P5-01 | Pending |
| P5-03 | Client decode and frame pacing | `AirDesk/Display/DesktopSurface.swift`, `DisplayCoordinator.swift`; web endpoint surface path | Pacing to display refresh; dropped-frame diagnostics; latency/CPU metrics; no false glass-to-glass claim | P5-02 | Pending |
| P5-04 | Persistent PTY daemon | New `core/airdeskd/**`, `AirDesk/Remote/SSHPTYSession.swift`, `RemoteTerminalController.swift`; tests | `airdeskd` byte-tees raw PTY over ADFP; multiple clients attach; replay buffer bounded; leases enforced | P1-03, P1-07 | Pending |
| P5-05 | OSC 133 replay and handoff | `AirDesk/Remote/**`, `AirDesk/Web/TerminalBridge.swift`, `AirDeskTests/RemoteSSHReattachTests.swift` | Reconnect replays active command records without corrupting TUIs; second device attaches; zero lost acknowledged bytes | P4-08, P5-04 | Pending |
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
| DeviceAgent contract | `protocol/fixtures/device-agent.json` | Identity/capability/health shape and canonical URIs |
| WIT conformance | `protocol/abi/check.sh` | 0.2 world validity; 0.3 separate; no mixed worlds |
| Core FFI smoke | `core.yml` | Rust tests, UniFFI bindings, wasm build, Swift/Kotlin smoke |
| Transport evidence | Structured run JSON | Required metadata present; no unrecorded result |
| Capability negative tests | iOS/Android/web | Denied/expired/revoked/busy fail closed |

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
| Iroh 1.4.x FFI unavailable or incompatible | Keep 1.2.0 product pin; use research probe only; do not claim multipath/roaming support until FFI and tests exist |
| ScreenCaptureKit is the wrong host API | Decide ReplayKit vs macOS host before writing capture code; kill zero-copy iOS claim if no viable host path |
| libghostty-vt/WebMCP/renderingPaused APIs differ from source plan | Treat as research; benchmark and license-check before replacement; keep current wterm path |
| UWB unavailable or privacy-sensitive | Keep Bonjour/manual fallback; require threat-model review; do not make proximity mandatory |
| CRDT migration corrupts workspace | Keep current merge-class model until operation log has deterministic corpus and rollback; no workspace-wide CRDT without ADR |
| Android parity claimed without CI | Block parity claims until `android.yml` is green; no exception |
| ADR-013/014/018 promoted early | Keep `Proposed` until evidence gates; review at each phase exit |
| Hardware qualification blocks release | Ship code-level features with truthful “unqualified” diagnostics; keep Cast/hardware dev-only |

## 10. Immediate next sprint

1. P1-05/P1-06: add the remote runtime provider and placement diagnostics behind an explicit registration path.
2. P2-01: write the `DeviceAgent` contract and canonical capability fixture before adding capture or transfer code.
3. P5-01: write the host capture platform decision; do not start with ScreenCaptureKit on the current iOS target.
4. Keep `milestones.md` unchanged until a task actually passes its gate.

## 11. ADR and documentation updates

| Document | Update |
| --- | --- |
| New ADR-024 | Shared Rust core, UniFFI/C-ABI/WASM boundary, fixture ownership, cutover and rollback |
| New ADR-025 | Host capture and media pipeline platform decision |
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

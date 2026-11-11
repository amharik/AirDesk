# AirDesk 100x/1000x Masterplan — Execution Breakdown

- **Status:** Planning only — no implementation commitment and no ADR promotion
- **Date:** 2026-11-10
- **Baseline:** `dev` at `90555d9`, plus the verified P5-03 iOS client decode/frame pacing path
- **Input:** User-supplied 100x product / 1000x UX masterplan
- **Related:** `milestones.md`, `docs/planning/workspace-fabric-plan.md`, `docs/planning/release-roadmap.md`, ADR-001 through ADR-023

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

- The product pins `IrohLib` 1.2.0 in `project.yml` and `iroh-android` 1.2.0 in `android/app/build.gradle.kts`. Only `research/iroh-probe/Cargo.toml` uses `iroh = 1.4.1`. Product upgrade is a separate, gated task.
- `protocol/rust/` currently contains packed/movement codecs, not a shared core or FFI layer.
- `libghostty-vt`, OSC 133 handling, `renderingPaused`, WebMCP, one-euro filtering, UWB discovery and zero-copy media capture are not present in tracked source. ResourceCompound and BLAKE3 blob handles are implemented and covered by cross-language fixtures.
- The current app target is iOS 17.5 with Mac Catalyst disabled. `ScreenCaptureKit` is a macOS API and cannot be used by the current iOS host target. The host strategy must choose ReplayKit/broadcast extension, a separate macOS host target, or an external host process before implementation.
- ADR-013 is `Proposed`; `XPORT-02` cannot be signed off without measurements.
- ADR-014 deliberately keeps the browser endpoint loopback-only. Non-loopback browser transport is an architecture decision, not a host-binding change.
- ADR-018 is still `Proposed`; a WIT package and host ABI do not exist.
- Android CI exists and is green; parity claims still require hardware qualification and live-network evidence.
- The web terminal has `readText()` but no OSC 133 command-block model, no `renderingPaused` integration and no WebMCP authorization layer.
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
| P0-05 | Add shared-core boundary ADR | `docs/adr/024-shared-core-and-ffi-boundary.md`, `docs/adr/README.md` | ADR is `Proposed`; defines what may move into Rust, compatibility fixtures, rollback and ownership | P0-01..03 | Proposed |
| P0-06 | Freeze Phase 1 contracts | `protocol/fixtures/**`, `docs/planning/100x-masterplan-execution.md`, `milestones.md` | ADFP envelope, remote runtime, DeviceAgent and WIT contracts have named owners and fixture paths | P0-01..05 | Contract paths frozen; ADFP, ResourceCompound/blob, remote runtime provider, DeviceAgent and WIT fixtures verified |

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
| P1-09 | Iroh product upgrade spike | `project.yml`, `android/app/build.gradle.kts`, `AirDesk/Fabric/**`, `research/iroh-probe/` | Verify IrohLib/FFI 1.4.x availability; document API gaps; test path migration/roaming and relay diagnostics on loopback before product pin changes | P0-04 | Research |
| P1-10 | Transport evidence upgrade | `scripts/research/transport_bench.ts`, `run-transport.sh`, `run-iroh*.sh`, `research/scenarios/**`, `docs/research/runs/**` | `cpu_percent`, build/runtime/network/device metadata; p50/p95/p99 recorded; no claim without method | P0-04 | Partial |

### Phase 2 — Agent parity and ABI (16–22 engineer-weeks)

| ID | Task | Files | Done when | Depends | Status |
| --- | --- | --- | --- | --- | --- |
| P2-01 | Cross-platform `DeviceAgent` contract | `AirDesk/Capabilities/DeviceAgent.swift`, `android/.../agent/DeviceAgent.kt`, `web/src/capability/**`; shared fixtures | Identity, capabilities, request/release, subscribe, health and typed lifecycle on all clients; availability and authorization remain independent | P0-06 | Verified, committed |
| P2-02 | iOS camera capture streaming | `AirDesk/Capture/CameraCaptureSource.swift`, `CameraCaptureStreamController.swift`; tests with mock source | Explicit authorization/lease gate; bounded frames/backpressure; cancel and permission-denied typed; no physical camera required for unit tests | P2-01 | Verified, committed |
| P2-03 | iOS document roots and file transfer | `AirDesk/Resources/ResourceRoot.swift`, `ResourceTransferService.swift`; tests | App-scoped/user-selected roots; path/symlink confinement; bounded read/write/stat; transfer events; no device-wide access | P2-01 | Verified, committed |
| P2-04 | Native capability lease and invocation enforcement | `AirDesk/Capabilities/CapabilityLeaseManager.swift`, `CapabilityAuthorizer.swift`, `CapabilityInvocationService.swift` | Issuance/expiry/revocation; provider/root issuer checks; remote invocation denied without matching lease/`cnf`; audit event | P2-01, P1-02 | Verified, committed |
| P2-05 | Android agent contract and canonical URIs | `android/.../agent/DeviceAgent.kt`, `capabilities/**`, `protocol/AdfpCapabilityMapper.kt` | Canonical `airdesk://fs/documents/read` plus `write`; camera authorization aligned with ADR-012; tests | P2-01 | Verified, committed |
| P2-06 | Android precision input controller | `AndroidTrackpadSurface.kt`, `AndroidInputRouter.kt`, `InputLease*` equivalents; tests | 120 Hz local cursor path; packed movement; no stuck input; multi-controller arbitration | P2-01, P4-01 | Pending |
| P2-07 | Android workspace/terminal bridge | `AndroidWorkspaceHost.kt`, `AndroidDesktopBridge.kt`, `DisplaySessionController.kt`; tests | Bundled DesktopShell drives workspace host and terminal bridge; reconnect preserves identity; truthful diagnostics | P1-05, P2-01 | Verified, committed |
| P2-08 | Android MediaProjection/MediaCodec stream | `AndroidMediaCodecStream.kt`, `DisplaySessionController.kt`; tests | Registered display pipeline; hardware codec capability detection; fallback and typed failure; physical qualification separate | P2-07 | Verified, committed |
| P2-09 | Android persistent SSH service | `AndroidSSHService.kt`, `RemoteSSH*`; tests | Foreground service; reattach and second-device handoff use same protocol as iOS; process survival tested remotely | P1-07 | Code complete; physical survival gate pending |
| P2-10 | WIT host ABI 0.2 | `protocol/abi/wit/airdesk-host-abi.wit`, `protocol/abi/README.md`, `protocol/abi/check.sh` | `vfs-service`, `pty-service`, `display-sink`, typed errors, lease revalidation, 256 KiB PTY credits, no display frame submission | P2-01 | Verified, committed |
| P2-11 | WIT 0.3 evaluation and conformance | `protocol/abi/wit/airdesk-host-abi-0_3.wit`, `protocol/abi/conformance/**` | Separate 0.3 world using `stream<T>`/`future<T>`; no mixed worlds; conformance harness runs where tooling exists | P2-10 | Static gate complete; runtime conformance pending |

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
| P5-01 | Host capture platform decision | New ADR-025; `AirDesk/Display/**`, `project.yml` | Decision records iOS ReplayKit/broadcast extension vs separate macOS host vs external host; ScreenCaptureKit only if a macOS target exists | P0-05 | Verified, committed |
| P5-02 | Zero-copy encoder pipeline | `AirDesk/Display/ScreenCapturePipeline.swift`, `VideoToolboxEncoder.swift`, `DisplayCoordinator.swift`; `android/.../AndroidMediaCodecStream.kt` | Capture surface -> encoder with bounded queues; HEVC/AV1 capability detection; keyframe/recovery; no unbounded memory | P5-01 | Verified, committed (iOS host path) |
| P5-03 | Client decode and frame pacing | `AirDesk/Display/DesktopSurface.swift`, `DisplayCoordinator.swift`; web endpoint surface path | Pacing to display refresh; dropped-frame diagnostics; latency/CPU metrics; no false glass-to-glass claim | P5-02 | Verified, committed (iOS decode/pacing path) |
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

1. P2-09 retains one physical gate: install the debug APK on an Android device, connect to a real SSH server, background the app, verify the foreground service/session survives, then verify reattach and second-device handoff. Do not mark P2-09 `Verified` from JVM tests alone.
2. P2-10 and the P2-11 static gate are complete: the 0.3 world is separate, uses `stream<T>`/`future<T>`, and the conformance manifest records every runtime as `not-run`. Runtime conformance and lease-enforcement integration remain pending; do not claim runtime qualification from the WIT check alone.
3. P2-04 now supplies native grant-chain, lease, revocation and `cnf` authorization with audit events on top of P1-02 workspace-key evidence. Production remote invocation transport wiring remains pending and must not be claimed from the standalone service tests.
4. P2-06 remains blocked on P4-01 for the one-euro pointer filter dependency.
5. P5-03 is code-level only until transport/UI wiring and physical-display qualification exist; do not claim glass-to-glass latency.
6. Keep `milestones.md` unchanged until a task actually passes its gate.

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

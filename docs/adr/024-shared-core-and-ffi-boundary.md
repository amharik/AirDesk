# ADR-024: Shared core and FFI boundary

- **Status:** Proposed — implementation and fixture-equality gates required
- **Date:** 2026-11-09
- **Deciders:** Engineering lead, security owner, platform owners
- **Scope:** Shared Rust core, Swift/Kotlin/wasm bindings, compatibility fixtures, cutover, rollback and ownership
- **Supersedes:** None
- **Amends:** ADR-003, ADR-008, ADR-010, ADR-017, ADR-018, ADR-021
- **Related:** ADR-004, ADR-011, ADR-012, ADR-013, ADR-022, ADR-023

## Context

The same protocol and input semantics are currently implemented in several places:

- Swift ADFP and input codecs;
- TypeScript browser codecs;
- Kotlin Android ADFP and fabric sessions;
- Rust protocol research code;
- Swift, TypeScript, Kotlin and Rust pairing/crypto helpers.

These copies already require fixture checks to stay aligned. Adding resource-compound RPC, blob handles, movement filtering, remote runtime state and DeviceAgent contracts will increase the number of duplicated state machines. The masterplan proposes a shared Rust core to reduce that duplication.

A shared core is not free:

- an FFI boundary is security-sensitive and easy to misuse;
- UniFFI, JNI, Swift binary packaging and WASM bindings have different lifecycle and threading rules;
- iOS and Android platform APIs, permissions, Keychain/Keystore, PTY, Iroh endpoints and display capture cannot move into portable Rust;
- crypto extraction can create drift from the audited Swift/web paths;
- deleting native implementations before fixture parity removes the rollback path.

This ADR defines what may move, what must stay native, how compatibility is proved, and how a cutover can be reversed.

## Decision

### 1. Add a workspace under `core/`; do not replace the product path yet

The shared core is a Cargo workspace:

```text
core/
  Cargo.toml
  airdesk-protocol/   ADFP envelopes, FlatBuffers validation and typed payloads
  airdesk-core/       deterministic state machines and pure algorithms
  airdesk-ffi/        UniFFI/C-ABI exports for Swift and Kotlin
  airdesk-wasm/       browser bindings
```

- The core is additive until each migration gate passes.
- No existing native implementation is deleted in the same change that introduces its Rust replacement.
- The product does not depend on the core being present at runtime until its feature flag is enabled.
- `core/` must be buildable and testable without Xcode, Android Studio or a browser.

### 2. Rust owns deterministic, platform-neutral logic first

The initial migration set is deliberately narrow:

- ADFP envelope parsing and serialization, file identifier/version/size/expiry checks;
- shared typed payload validation;
- resource-compound and blob-handle semantics;
- input/movement normalization and the one-euro filter;
- canonical JSON/fixture hashing and deterministic test vectors;
- pure capability-lease attenuation and revocation-set evaluation;
- protocol constants and compatibility checks.

Later candidates require an amendment or a new ADR:

- cryptographic primitives and key schedules;
- CRDT/operation-log merge;
- transport framing above the Iroh/WebSocket adapter;
- remote runtime state machines.

Crypto remains on the audited existing paths until RFC vectors, cross-language fixtures, independent review and constant-time/performance evidence exist for the Rust path. No crypto cutover is allowed on the strength of one implementation.

### 3. Platform I/O and authority remain native

The following do not move into the shared core:

- SwiftUI/Compose/browser UI and lifecycle;
- Keychain, Android Keystore, Secure Enclave and platform identity storage;
- Iroh endpoint ownership and platform networking;
- SSH, local PTY and process spawning;
- display capture, presentation and `OriginPolicy`;
- camera, microphone, location and OS permission prompts;
- file-picker and unrestricted filesystem access;
- workspace authority, host-role handoff and session ownership;
- audit logging and user-visible consent.

The core receives data and returns typed results. It does not receive an ambient handle to the host process, filesystem, network or platform permission APIs.

### 4. Binding choices

| Consumer | Binding | Rules |
| --- | --- | --- |
| Swift/iOS | UniFFI-generated Swift from `airdesk-ffi` | XCFramework or static library pinned by checksum; no runtime downloads |
| Kotlin/Android | UniFFI-generated Kotlin/JNI from `airdesk-ffi` | ABI per Android ABI; no reflection-based dispatch |
| Browser | `wasm-bindgen`/WASI from `airdesk-wasm` | Browser-safe subset only; no native filesystem/network imports |
| Rust tests/probes | direct crate APIs | Must not depend on platform bindings |

- UniFFI is the default. A hand-written C ABI is allowed only if UniFFI cannot express a required type safely, and needs an ADR amendment.
- Every exported operation has a versioned, typed error. Unknown required versions fail closed.
- No secret is logged at the boundary. Panics are caught at the FFI edge and mapped to a typed internal error; panic payloads and host paths are not returned to callers.
- Stateful handles are `Send + Sync` or are explicitly documented as single-threaded. The core does not start a global async runtime or call back into platform code while holding a lock.
- The core must not depend on a specific FlatBuffers runtime version at the ABI edge; wire compatibility is defined by the schema and fixtures, not by Rust type layout.

### 5. Fixtures are the source of truth

Cross-language compatibility is demonstrated by committed golden fixtures, not by similar-looking code.

```text
protocol/fixtures/adfp/                 envelope + payload fixtures
protocol/fixtures/resource-compound/    compound walk/open/read/clunk fixtures
protocol/fixtures/resource-blob/        BLAKE3 handle fixtures
protocol/fixtures/input/                movement and one-euro fixtures
protocol/fixtures/crypto/               pairing/key-schedule vectors
protocol/fixtures/device-agent/         DeviceAgent request/health fixtures
protocol/fixtures/host-abi/             WIT conformance fixtures
```

Rules:

- A fixture has an owner, schema version and expected result.
- Swift, TypeScript, Kotlin and Rust consume the same committed bytes.
- Generated bindings and fixtures are checked by `protocol/check.sh` and the core CI workflow.
- A fixture change is a compatibility change and requires review from every consumer owner.
- Tests must reject malformed, truncated, oversized, wrong-version and wrong-file-identifier inputs, not only round-trip valid ones.

### 6. Incremental cutover

A component may move to the core only after all of the following:

1. the fixture set covers valid and invalid behavior;
2. the Rust implementation passes those fixtures;
3. every current implementation passes the same fixtures;
4. differential/fuzz testing finds no divergence;
5. the new path is behind a feature flag or explicit registration;
6. the old path remains available for rollback for at least one release;
7. platform integration tests pass on iOS, Android and web as applicable;
8. dependency/licence checks pass;
9. performance, memory and startup regressions are measured and accepted;
10. the owning platform code is changed in a separate reviewable commit.

The order is: boundary and fixtures → read-only decode/validation → encode/write path → stateful algorithms → crypto only after a separate decision.

### 7. Rollback

- Each migrated component keeps a native fallback until the next release has shipped and the fallback has been exercised once.
- A feature flag or registration switch selects native or core.
- Rollback must not require a schema rollback or data migration.
- Wire-format changes require an additive schema change and a version gate; the core cannot silently reinterpret old bytes.
- Removing the fallback is an explicit task with its own tests and review.

### 8. Ownership

| Area | Owner |
| --- | --- |
| `core/Cargo.toml`, crate layout, Rust APIs | Core owner |
| `core/airdesk-ffi`, UniFFI surface | Core owner + platform owners |
| `core/airdesk-wasm`, browser subset | Core owner + web owner |
| Swift binding integration | iOS owner |
| Kotlin/JNI integration | Android owner |
| `protocol/fixtures/**` | Protocol owner with consumer review |
| `.github/workflows/core.yml`, Android/iOS/web gates | CI owner |
| ADR amendments and cutover approval | Engineering lead + security owner |

One owner changes a boundary at a time. Platform owners do not edit the FFI surface independently of the core owner.

## Consequences

### Positive

- One implementation for deterministic wire and algorithm logic.
- Cross-language drift is caught by fixtures rather than production bugs.
- Rust ownership and fuzzing can be applied to parsers.
- Android, iOS and web can share protocol fixes.
- A rollback path exists during migration.

### Negative

- Adds a Rust toolchain, FFI packaging and per-ABI build complexity.
- Adds a security-sensitive boundary and a second release artifact.
- UniFFI and WASM type coverage will not match all native types.
- Platform teams still own integration and lifecycle.
- Crypto extraction remains a separate, high-risk project.

## Acceptance gates

- `core/` builds on macOS and Linux with the pinned Rust toolchain.
- Swift and Kotlin bindings build from the same `airdesk-ffi` revision.
- Browser WASM builds without native filesystem or network imports.
- ADFP, resource, input and DeviceAgent fixtures produce identical results in Swift, TypeScript, Kotlin and Rust.
- Invalid, truncated, oversized and wrong-version inputs fail with the same typed error class.
- No platform I/O, permission, Keychain/Keystore, PTY, Iroh endpoint or display code appears in the core crates.
- The core starts no global async runtime and leaks no host paths or secrets through errors or logs.
- A migrated component can be switched back to its native implementation without a data migration.
- The native implementation is not deleted until the core path has shipped once and rollback has been exercised.
- Crypto remains native until ADR-022/ADR-023 fixture equality and an independent review are complete.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Keep all implementations native | Duplicates parsers and state machines across four languages; drift increases with resource RPC and blob handles |
| Move the entire app to Rust | UI, platform permissions, Iroh endpoint, PTY and display integration are platform-owned |
| One big-bang Rust rewrite | Removes rollback, blocks platform work and cannot be verified before cutover |
| Custom C ABI for all platforms | Memory-unsafe and drifts across Swift/Kotlin/JS; UniFFI gives typed bindings |
| Move crypto first | Highest risk and least tolerant of divergence; protocol/fixtures must come first |
| WASM-only shared core for native apps | Adds a runtime and sandbox boundary where a native library is simpler; keep WASM for the browser |

## Open questions

- Which UniFFI version and Rust toolchain are pinned for the first implementation?
- Does the iOS packaging path need an XCFramework or can a static library plus SwiftPM binary target be used?
- Is Android 16 KB page-size support required for the first `airdesk-ffi` release?
- Which benchmark corpus and thresholds gate a component cutover?

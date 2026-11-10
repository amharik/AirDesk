# ADR-018: Native device agents and capability host ABI

- **Status:** Proposed — platform agent and capability ABI gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — peer review: WASI 0.2 Component Model WIT host ABI
- **Updated:** 2026-11-03 — peer review round 3: cross-runtime is a gate; WASI 0.3 `stream<T>`; `forkpty()` macOS only; no display frame submission
- **Updated:** 2026-11-10 — WIT package `airdesk:host-abi@0.2.0`, contract fixture and `protocol/abi/check.sh` landed; per-runtime conformance remains pending
- **Deciders:** Engineering lead, security owner
- **Scope:** DeviceAgent contract, native adapters, capability descriptors, leases, host ABI, platform permissions
- **Supersedes:** None
- **Amends:** ADR-004, ADR-012, ADR-014
- **Related:** ADR-010, ADR-011, ADR-013, ADR-016, ADR-017

## Context

AirDesk targets heterogeneous devices with different platform permissions, process models, background limits and hardware access. Requiring Wanix on every device would make the fabric depend on one runtime and would not expose native platform functionality safely.

The blueprint makes native agents the integration boundary: devices contribute capabilities, and runtimes access those capabilities only through authorized adapters.

## Decision

### 1. Every participating platform has a native agent

A native agent exposes device functionality through a stable host interface. It is responsible for:

- device identity;
- capability advertisement;
- camera, microphone, filesystem, sensor and input permissions;
- native process and application integration;
- notifications;
- display integration;
- network and background constraints;
- health and lifecycle events.

Wanix does not replace the native agent.

### 2. DeviceAgent contract

```text
DeviceAgent
  identity()
  capabilities()
  requestCapability(cap_uri, request)
  releaseCapability(leaseId)
  subscribe(eventType, handler)
  health()
```

Each platform implements the contract with its own native APIs. The contract is logical; it does not require an RPC boundary between components in the same process.

### 3. Capability descriptors are sufficient for safe placement

```text
CapabilityDescriptor
  id, providerDeviceId
  type, version
  availability: available | busy | restricted | unavailable
  constraints
  permissions[]
  transport[]
  executionModel
  lifecycle
```

Initial capability namespaces include camera, audio input, pointer, keyboard, display output, file storage, database storage, native compute, WASI compute and location.

Advertisement is not permission. The orchestrator resolves a capability only after authorization and availability checks.

### 4. Access uses revocable leases

A capability lease contains:

- lease ID;
- device and `cap_uri`;
- workspace, application and requester IDs;
- granted operations;
- scope and constraints;
- issue and expiry times;
- revocation state;
- audit identifier.

Leases are time-bounded, scoped and revocable. Indefinite implicit access to device resources is prohibited.

### 5. Runtimes use a capability host ABI

- Wanix and other runtime providers access host functionality only through an explicit host adapter.
- The adapter enforces capability grants and platform permissions.
- The host adapter must not expose unrestricted filesystem, process or device access.
- On Wanix, map the ABI onto its existing file-service and host-exported-device boundary (`#web`, exported devices and scoped namespace binds) rather than adding a parallel unrestricted host bridge.
- A namespace import grants only what the namespace exposes; the ABI still checks workspace, application, lease and platform policy.
- The ABI is versioned independently of the runtime, namespace layout and ADFP wire versions.
- Unsupported host operations fail closed with a typed error.

### 5.1 Host ABI uses the WASI 0.2 Component Model

The host ABI is a **WASI 0.2 Component Model** contract expressed in WIT, not a custom C FFI or ad-hoc JSON plugin ABI. It imports `wasi:io/streams@0.2.0` and is consumed by native runtime worlds that may also import `wasi:filesystem/types@0.2.0` and `wasi:cli/run@0.2.0`, plus the AirDesk package `airdesk:host-abi@0.2.0`.

Cross-runtime portability is a **qualification gate, not a property**. A component is not assumed to run identically in Wanix and in the native Rust/Swift agent merely because both implement the same WIT. Each runtime must pass the `airdesk:host-abi` conformance suite for the interfaces it claims; until it does, a component is admitted per runtime and the manifest names the qualified runtime target.

WASI 0.3 changes the stream model: `wasi:io` is removed and its streams are re-expressed as component-model `stream<T>` / `future<T>`. The 0.2 interfaces above remain the baseline. When the native agent moves to 0.3, the ABI re-expresses `stdin`/`stdout`/`read-stream`/`write-stream` in terms of `stream<T>` rather than importing `wasi:io`; a mixed 0.2/0.3 deployment is a qualification failure, not a silent adapter.

| WIT interface | Bound protocol | Capability URI | Host resources | Enforcement |
| --- | --- | --- | --- | --- |
| `airdesk:host-abi/vfs-service` | AD-RESOURCE | `airdesk://fs/<mount_id>/<mode>` | `node { stat, open-at, read-stream, write-stream, readdir }`, `mount-capability(token) -> result<node, abi-error>` | Path canonicalization (`O_NOFOLLOW`, no `..` escape) matching Wanix VFS bind semantics |
| `airdesk:host-abi/pty-service` | AD-RUNTIME | `airdesk://pty/<profile_id>` | `pty-session { stdin, stdout, resize, kill, wait }`, `spawn(cmd, args, cols, rows)` | 256 KiB credit window bridging `SSHPTYSession` or a local PTY. `forkpty()` is available on the macOS agent only; the iOS agent uses its platform PTY/`posix_spawn` path |

The host ABI does **not** expose display frame submission. ADR-001 keeps rendering and frame ownership inside the display session; a host ABI `submit-frame` would create a second, unaudited presentation path and bypass ADR-005/ADR-014 `OriginPolicy`. Display input subscription and presentation state belong to the display-session interfaces, not to the native capability host.

- The WIT world declares the WASI 0.2 world/version explicitly; an unsupported world fails closed at placement.
- Each runtime's WIT support is recorded as a qualification result, and the manifest pins the qualified runtime target.
- WASI 0.3 async streams (`stream<T>`/`future<T>`, no `wasi:io`) are a forward-compatible target, not the baseline.
- Capability tokens are `COSE_Sign1` per ADR-012 and are validated at every host call, not only at mount.
- The ABI never exposes unrestricted filesystem, process, socket or device access.
- Traps, aborts and typed `abi-error` results are mapped to ADFP errors without leaking host paths or secrets.

### 6. Native execution remains first-class

- A device can be useful without running Wanix.
- Native applications, hardware acceleration and platform APIs are valid execution paths.
- A runtime provider may be unavailable on a platform without making the device unusable.
- Device agents must not assume that every workload runs in a browser or WASM sandbox.

### 7. Platform security remains authoritative

- iOS, Android, macOS, Windows and browser permission models remain in force.
- AirDesk grants do not override operating-system permission denial.
- A capability can be advertised but restricted by the platform.
- Revocation invalidates AirDesk leases but does not bypass platform revocation.

### 8. Device trust is not workspace membership

Pairing establishes device trust. It does not:

- grant workspace ownership;
- make the device a collaborator;
- grant all capabilities;
- authorize arbitrary input injection.

Those are separate authorization decisions.

## Consequences

### Positive

- Native functionality remains accessible.
- Wanix is optional on devices.
- Platform-specific restrictions remain enforceable.
- The fabric can support heterogeneous endpoints.
- Capability access is auditable and revocable.

### Negative

- Requires platform-specific agent implementations.
- Requires capability compatibility and versioning.
- Requires careful permission, lease and lifecycle management.
- A host ABI adds a security-sensitive boundary.

## Acceptance gates

- A device can expose and authorize a capability through a native agent.
- A capability request can be leased, used, expired and revoked.
- Wanix can access an approved host capability through the `airdesk:host-abi@0.2.0` WIT contract.
- Wanix and the native Rust/Swift agent each pass the `airdesk:host-abi` conformance suite for the interfaces they claim; cross-runtime equivalence is demonstrated per interface, not assumed from one WIT definition.
- A WASI 0.3 world is rejected unless the agent implements `stream<T>`/`future<T>`; no `wasi:io` import is silently shimmed.
- The host ABI exposes no display frame submission path.
- Wanix cannot bypass the host ABI to obtain unrestricted host access; every host call revalidates its lease.
- A device can run native workloads without Wanix installed.
- Platform permission denial is reported truthfully and cannot be overridden by an AirDesk grant.
- Pairing alone does not grant workspace ownership or optional capabilities.
- Device and capability schemas are versioned and fail closed on unsupported required versions.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Custom C FFI | Memory-unsafe across Swift/Rust and per-platform drift |
| Ad-hoc JSON plugin ABI | No typed resources, streams or capability errors |
| Embed a whole Wanix runtime per capability | Heavy and does not fit native-only devices |
| WIT Component Model host ABI with per-runtime qualification | Chosen: typed, versioned, language-neutral, and explicit about what each runtime must prove |

# Release roadmap

This is the implementation roadmap. Product scope is summarized in `docs/product/product-roadmap.md`.

> **Research-first amendment (2026-11-04):** Release sequencing below is paused while the universal compute fabric is evaluated. The active track is `universal-compute-fabric-research.md`; implementation resumes only after the R6 adopt/hybrid/stop decision.

## Release 1 — Stable personal workspace

**Goal:** A coherent, recoverable workspace on one device.

Deliverables:

- Workspace manifest, schema versioning and store.
- Desired/observed state separation.
- Runtime provider interface and task-driver profile.
- Wanix provider adapter.
- Native execution integration.
- Application manifest and lifecycle with per-provider WASI targets: `wasip1` on Wanix, `wasi-cli@0.2` on the native agent (`wasi-cli@0.3` only after qualification).
- Per-field merge metadata (`lww`, `append-log`, `manual`).
- Display/input state separated from workspace state.
- Truthful recovery and diagnostics.
- Shell decoupled from Wanix internals.

Gates:

- Workspace survives shell close and application/runtime failure.
- Corrupt or future schema is rejected safely.
- Wanix failure is reported, not hidden by a fallback runtime.
- A provider executes only its qualified `(provider, world)` pair; unsupported worlds or versions fail closed.
- No workspace credential or private key is stored in the manifest.

## Release 2 — Personal device fabric

**Goal:** A second device contributes an authorized capability.

Deliverables:

- Native device agent contract.
- Device identity and pairing.
- Capability registry and leases.
- ADFP AD-WS, AD-DEV, AD-CAP, AD-RUNTIME, AD-RESOURCE, AD-INPUT and AD-DISPLAY baseline.
- WorkspaceOrchestrator and SessionCoordinator integration.
- Phone controller and multi-controller arbitration.
- Phone camera and files capabilities.
- Direct transport path.

Gates:

- Pairing does not grant workspace ownership.
- Unauthorized capability requests fail closed.
- Device disconnect preserves workspace and desired state.
- Multi-pointer input does not create ambiguous keyboard focus.

## Release 3 — Universal display endpoints

**Goal:** Present a workspace beyond the host device.

Deliverables:

- Browser presentation endpoint.
- Local host agent with explicit loopback origin policy.
- External display integration.
- Android device agent.
- USB-C/HDMI qualification.
- AirPlay and Cast feasibility results.
- Single-threaded Wanix profile with `SharedArrayBuffer` and cross-origin-isolation detection.
- WebTransport qualification as a candidate browser data path.
- Display reconnect and recovery.

Gates:

- Browser endpoint cannot become workspace authority.
- Hosted endpoint threat model and CSP/SRI requirements are satisfied or the feature remains local-only.
- Browser endpoint starts single-threaded without `SharedArrayBuffer`; threaded mode is opt-in.
- WebTransport negotiation falls back to WebSocket when unavailable.
- Display reconnect does not recreate the workspace.
- Cast remains development-only until hardware qualification passes.

## Release 4 — Distributed execution

**Goal:** Run workloads on the most appropriate device.

Deliverables:

- Remote Wanix provider.
- 9P remote-namespace feasibility spike for remote Wanix.
- Placement policies.
- Remote terminal execution.
- Remote application provider with AD-CAP protocol negotiation.
- RDP RAIL and Xpra experiments, preferring Xpra-style persistent reattach.
- Encrypted workspace synchronization using merge metadata.
- WASI 0.3 evaluation after Wanix and toolchain qualification.

Gates:

- Placement is explicit and explainable.
- A 9P namespace import is scoped and cannot bypass capability leases.
- Remote execution respects capability leases and quotas.
- Network loss produces typed failure and recoverable observed state.
- Remote application persistence is reported truthfully.
- Sync does not introduce silent multi-writer corruption or workspace-wide CRDTs.

## Release 5 — Intent and collaboration

**Goal:** Operate and share workspaces at a higher level.

Deliverables:

- Intent-driven tasks.
- Approval-gated agent operations.
- WebAuthn/FIDO2 user identity, separate from device identity.
- Shared workspace membership and roles.
- Collaboration permissions and audit.
- Shared resource semantics.
- CRDTs confined to shared documents.
- Optional group sessions.

Gates:

- Destructive agent operations require explicit approval.
- User identity and device trust remain separately testable.
- Membership and revocation are testable.
- Shared state has an explicit conflict model.
- Collaboration is not inferred from pairing or controller attachment.

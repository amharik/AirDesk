# Release roadmap

This is the implementation roadmap. Product scope is summarized in `docs/product/product-roadmap.md`.

## Release 1 — Stable personal workspace

**Goal:** A coherent, recoverable workspace on one device.

Deliverables:

- Workspace manifest, schema versioning and store.
- Desired/observed state separation.
- Runtime provider interface.
- Wanix provider adapter.
- Native execution integration.
- Application manifest and lifecycle.
- Display/input state separated from workspace state.
- Truthful recovery and diagnostics.
- Shell decoupled from Wanix internals.

Gates:

- Workspace survives shell close and application/runtime failure.
- Corrupt or future schema is rejected safely.
- Wanix failure is reported, not hidden by a fallback runtime.
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
- Display reconnect and recovery.

Gates:

- Browser endpoint cannot become workspace authority.
- Hosted endpoint threat model and CSP/SRI requirements are satisfied or the feature remains local-only.
- Display reconnect does not recreate the workspace.
- Cast remains development-only until hardware qualification passes.

## Release 4 — Distributed execution

**Goal:** Run workloads on the most appropriate device.

Deliverables:

- Remote Wanix provider.
- Placement policies.
- Remote terminal execution.
- Remote application provider.
- RDP RAIL and Xpra experiments.
- Encrypted workspace synchronization.

Gates:

- Placement is explicit and explainable.
- Remote execution respects capability leases and quotas.
- Network loss produces typed failure and recoverable observed state.
- Sync does not introduce silent multi-writer corruption.

## Release 5 — Intent and collaboration

**Goal:** Operate and share workspaces at a higher level.

Deliverables:

- Intent-driven tasks.
- Approval-gated agent operations.
- Shared workspace membership and roles.
- Collaboration permissions and audit.
- Shared resource semantics.
- Optional group sessions.

Gates:

- Destructive agent operations require explicit approval.
- Membership and revocation are testable.
- Shared state has an explicit conflict model.
- Collaboration is not inferred from pairing or controller attachment.

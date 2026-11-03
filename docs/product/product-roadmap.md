# Product roadmap

This roadmap follows the revised architecture blueprint. Dates are intentionally omitted until the preceding release gates pass.

## Release 1 — Stable personal workspace

**Objective:** Make AirDesk useful as a coherent workspace on one device.

- Stabilize the existing native shell.
- Define workspace manifest, schema versioning and desired/observed state.
- Add device-local persistence and truthful recovery.
- Introduce the runtime provider interface.
- Integrate Wanix through a provider adapter and task-driver profile.
- Preserve native execution.
- Define the application manifest and lifecycle with WASI 0.2 worlds.
- Add per-field `lww`, `append-log` or `manual` merge metadata now.
- Separate display and input state from workspace state.

**Exit:** A user can open a workspace, use applications, close the display session and recover the workspace without losing logical state.

## Release 2 — Personal device fabric

**Objective:** Let a second device contribute capabilities to the workspace.

- Native device agent.
- Device identity and pairing.
- Capability registry, leases and scoped authorization.
- ADFP baseline.
- `WorkspaceOrchestrator` and `SessionCoordinator` integration.
- Phone-as-controller.
- Phone camera and files as explicit capabilities.
- Multi-controller input arbitration.
- Direct transport connectivity.

**Exit:** A paired device can provide an authorized capability to an active workspace, and the workspace remains recoverable after that device disconnects.

## Release 3 — Universal display endpoints

**Objective:** Present the workspace across common display environments.

- Browser presentation endpoint.
- Local host agent.
- External display integration.
- Android device agent.
- USB-C/HDMI qualification.
- AirPlay and Cast feasibility or compatibility testing.
- Single-threaded Wanix browser profile with `SharedArrayBuffer` detection.
- WebTransport qualification as a candidate browser data path.
- Display reconnection and restoration.

**Exit:** A workspace can be presented on supported native and browser endpoints without making the endpoint the workspace authority.

## Release 4 — Distributed execution

**Objective:** Run workloads on the most appropriate participating device.

- Remote Wanix runtime provider, including a 9P remote-namespace feasibility spike.
- Runtime placement policies.
- Remote terminal execution.
- Remote application provider with AD-CAP protocol negotiation.
- RDP RAIL and Xpra experiments, preferring Xpra-style reattach.
- Resource access and transfer.
- Encrypted workspace synchronization using merge metadata, not workspace-wide CRDTs.
- WASI 0.3 evaluation after Wanix/toolchain qualification.

**Exit:** An application can execute on a different device from the active display with explicit placement, authorization and failure handling.

## Release 5 — Intent and collaboration

**Objective:** Make the workspace easier to operate and share.

- Intent-driven task interface.
- Approval-gated agent operations.
- WebAuthn/FIDO2-based user identity, separate from device identity.
- Shared workspace identity and membership.
- Roles and permissions.
- Shared resource semantics.
- Collaboration audit and revocation.
- CRDTs confined to shared documents.
- Optional group sessions.

**Exit:** Multiple authenticated users can collaborate in a shared workspace with explicit ownership and access policies.

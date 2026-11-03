# Device fabric

The device fabric is the set of devices that can contribute capabilities to a workspace.

## Device roles

A device may be:

- a workspace host;
- a native execution provider;
- a portable runtime provider;
- a controller;
- a display endpoint;
- a capability provider;
- several of these at once.

Roles are negotiated per session and per workspace. A role does not imply workspace ownership.

## Native agents

Each platform exposes functionality through a native agent. The agent owns platform permission prompts, hardware access, background rules and process integration. See `device-agent-architecture.md`.

## Capabilities

Capabilities are scoped, versioned descriptors such as:

- `camera.capture`;
- `audio.input`;
- `input.pointer`;
- `input.keyboard`;
- `display.output`;
- `storage.files`;
- `storage.database`;
- `compute.native`;
- `compute.wasi`;
- `location.read`.

Capability advertisement is not permission. A capability request must be authorized against device identity, workspace, application, scope, consent, lease validity and platform permission.

## Leases

A capability lease is time-bounded, scoped and revocable. It identifies the workspace, application, requester, provider, operations, expiry and audit record. A lease cannot outlive its grant or workspace authorization.

## Trust boundaries

- Pairing establishes device trust only.
- Workspace ownership is separate.
- Controller attachment is a session role.
- Capability access is a separate authorization decision.
- Revocation invalidates trust and leases; it does not delete the workspace.

## Heterogeneity

Devices differ in:

- available capabilities;
- native execution support;
- Wanix support;
- background execution;
- display integration;
- transport reachability;
- power and thermal constraints.

The fabric reports these differences explicitly. It does not assume a uniform runtime or a uniform permission model.

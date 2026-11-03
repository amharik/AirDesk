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

## Fabric planes

The fabric is partitioned into three planes so discovery, authority and data have independent failure modes.

### Discovery and pairing plane

Local peers advertise `_airdesk._tcp.local.` for the control endpoint and, when a WebTransport listener is running, `_airdesk._udp.local.` (RFC 6762). Canonical TXT keys are `txtvers=1`, `adfp_ver=1.0`, `device_type=host|controller|display`, `certhash_current=<sha256>` and `certhash_next=<sha256>` for rotated WebTransport ECDSA certificates. Stable `dev_id` and `role_mask` are not advertised; the instance name is a random per-boot label. mDNS is optional; QR or authenticated rendezvous is the fallback. Pairing uses RFC 9383 SPAKE2+ with a channel binding: the TLS 1.3 exporter (`EXPORTER-AirDesk-Pairing-v1`) for native/native pairs, and the host certificate hash from the pairing payload for browser endpoints, per ADR-011 §4.2. Certificate hashes are accepted only from the pairing payload or a signed advertisement.

### Control and authority plane

Authority is split by duty (ADR-020):

- The `WorkspaceHost` is the single writer for manifest commits, structural sequencing (`workspace_seq:u64`, ADR-016) and orchestration.
- The display session's `SessionCoordinator` owns input lease arbitration (`lease_epoch:u64`, ADR-015). It does not depend on the workspace host being reachable.
- Root capability grants are issued by the provider device's user approval or the workspace owner key, not by the coordinator or the requester (ADR-012 §4).

The coordinator is a control-plane service and is none of these authorities.

### Data and execution plane

High-frequency `PackedPointerFrame` movement datagrams (Channel 1), reliable input edges (Channel 1R) and AD-RUNTIME / AD-RESOURCE streams (Channels 2..K) route over direct peer-to-peer WebTransport (HTTP/3 QUIC) or WebSocket between the active controller, display sink and runtime provider. Direct LAN connectivity is preferred; an encrypted relay is never a hidden prerequisite.

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

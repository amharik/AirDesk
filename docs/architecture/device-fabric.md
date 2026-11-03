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

Local peers advertise `_airdesk._udp.local.` (RFC 6762) with TXT records carrying `txtvers=1`, `dev_id`, `role_mask`, `adfp_ver=1.0`, `certhash_current=<sha256>` and `certhash_next=<sha256>` for rotated WebTransport ECDSA certificates. mDNS is optional; QR or authenticated rendezvous is the fallback. Pairing uses RFC 9383 SPAKE2+ bound to the TLS 1.3 exporter (`EXPORTER-AirDesk-Pairing-v1`), per ADR-011.

### Control and authority plane

A single workspace authority sequences structural workspace mutations (`workspace_seq:u64`, ADR-016), issues attenuated `COSE_Sign1` capability tokens (ADR-012), and arbitrates multi-controller input ownership (`lease_epoch:u64`, ADR-015). The coordinator is a control-plane service, not the workspace authority.

### Data and execution plane

High-frequency `PackedPointerFrame` datagrams (Channel 1) and AD-RUNTIME / AD-RESOURCE streams (Channels 2..K) route over direct peer-to-peer WebTransport (HTTP/3 QUIC) or WebSocket between the active controller, display sink and runtime provider. Direct LAN connectivity is preferred; an encrypted relay is never a hidden prerequisite.

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

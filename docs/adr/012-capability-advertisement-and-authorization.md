# ADR-012: Capability advertisement, invocation and authorization

- **Status:** Proposed — capability and authorization gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — capability leases and application context added
- **Updated:** 2026-11-03 — peer review: compact COSE_Sign1 capability tokens with bounded delegation depth
- **Updated:** 2026-11-03 — peer review round 3: provider/owner root issuance, `jti`, `cnf`, session-`generation` `epoch_id`, `restricted` availability
- **Amended by:** ADR-020 (workspace host role and authority handoff)
- **Deciders:** Security owner, engineering lead
- **Scope:** Capability descriptors, leases, grants, invocation, resolution, audit, revocation, application context
- **Supersedes:** None
- **Related:** ADR-001, ADR-005, ADR-008, ADR-010, ADR-011, ADR-013, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018, ADR-019, ADR-020
- **Counters:** `docs/architecture/identifiers-and-counters.md`

## Context

`RuntimeCapabilities` is a set of booleans that describes a runtime, not a distributed device fabric. It does not express availability, permission requirements, resource limits, transport, expiry or revocation.

AirDesk needs devices to contribute specific capabilities without granting wholesale access to the device.

## Decision

### 1. Capabilities are versioned interfaces

A capability descriptor contains:

| Field | Purpose |
| --- | --- |
| `cap_uri` | Canonical identifier, for example `airdesk://media/camera/capture`. This is the only capability identifier; there is no separate dotted form on the wire |
| `version` | Capability-interface version |
| `providerDeviceId` | Device offering the capability |
| `inputSchema` / `outputSchema` | Typed invocation contract |
| `permissions` | Required user or workspace permissions |
| `execution` | Local, streaming or remote; cancellable and resumable flags |
| `constraints` | Resolution, latency, resource or sandbox limits |
| `transport` | Transport channel used to invoke it |

Capability identifiers are semantic. A device does not need to expose its operating system or implementation.

### 2. Availability and authorization are separate

Do not combine them in one status field.

| Axis | Values |
| --- | --- |
| Availability | `available`, `busy`, `restricted`, `unavailable` |
| Authorization | `ungranted`, `granted`, `denied`, `revoked` |

`restricted` means the capability exists but policy or local state limits its use (for example, camera while the screen is locked, or a quota-limited runtime). It is distinct from `busy` (temporarily occupied) and `unavailable` (not present or not reachable).

A capability can be available but ungranted. It can be granted but currently unavailable. The UI must not imply that availability is permission.

A **grant** is the durable signed policy decision. A **lease** is the short-lived runtime access derived from a grant. Holding one does not imply the other: a grant with no lease authorizes nothing at runtime, and a lease cannot exist without a grant.

### 3. Grants are scoped, short-lived and auditable

A grant contains:

- `cap_uri` and capability version (the `cap_uri` *is* the capability identifier; there is no separate numeric ID on the wire);
- provider device;
- resource scope;
- issuing workspace and user context;
- creation time and expiry;
- grantor;
- audit identifier;
- revocation status.

Do not grant `filesystem.access`. Grant scoped capabilities such as:

- `airdesk://fs/documents/read`;
- `airdesk://fs/documents/write`;
- `airdesk://media/camera/capture`;
- `airdesk://clipboard/read`;
- `airdesk://compute/wasm/execute`.

High-impact capabilities require explicit user approval. Expired, revoked or out-of-scope grants are denied.

### 4. Grant issuance and revocation are explicit

- A **root grant** is issued only by the authenticated user on the provider device, or by the workspace owner key acting for that user. A workspace host, coordinator or requester cannot mint a root grant (ADR-020 §3).
- The issuer signs the grant with a grant-signing key bound to the device identity from ADR-011.
- The verifier is the provider device or the provider's local policy engine.
- The coordinator may distribute revocation records but must not mint grants or leases.
- A grant names its issuer, subject device, provider device, scope, expiry and revocation sequence.
- Revocation records are signed and sequence-numbered.
- A provider that cannot obtain a current-enough revocation record fails closed for high-impact capabilities.
- Offline providers may accept a bounded-staleness revocation window; the window is explicit per capability.
- Revocation invalidates new invocations; an in-flight invocation is cancelled unless the capability declares a safe completion path.

### 4.1 Capability leases are the bounded access object

A **capability lease** is the time-bounded authorization a requester holds for a capability. A signed grant records the policy decision; the lease records the active, scoped access.

A lease contains:

- lease ID;
- device and `cap_uri`;
- workspace ID;
- requesting application ID;
- requester device and session IDs;
- granted operations and resource scope;
- issue time and expiry;
- revocation state;
- usage constraints;
- audit identifier.

Rules:

- A lease is required for every non-public capability invocation.
- The workspace and application context are part of the authorization decision.
- A lease cannot outlive its grant or workspace authorization.
- A lease is scoped to one application instance unless the capability contract explicitly permits sharing.
- A lease may be revoked without revoking unrelated capabilities.
- The provider enforces the lease; the requester cannot self-extend it.
- A lease does not grant workspace ownership or collaboration rights.

### 4.2 Grant tokens are compact COSE_Sign1

Grants and delegated capability chains use CBOR Object Signing and Encryption (`COSE_Sign1`) with Ed25519 signatures. Compact binary tokens are chosen over nested-JWT UCAN because UCAN adds DID resolution and per-hop envelope overhead at runtime; the compact form keeps the verify path small and dependency-free.

Token claims:

| Claim | Meaning |
| --- | --- |
| `iss` | Issuer device or user-authorized grant service (ADR-011 identity) |
| `sub` | Subject device or workload identity |
| `aud` | Provider device or capability resource |
| `jti` | Unique token ID; revocation and replay tracking key |
| `cap_uri` | Attenuated capability URI and the capability identifier, for example `airdesk://fs/workspace/readwrite` or `airdesk://pty/spawn` |
| `op` | Allowed operations within the capability |
| `nbf` | Not-before time |
| `exp` | Expiry time |
| `epoch_id` | Display-session `generation` the grant is valid for (ADR-020). It is **not** `lease_epoch`; leases change far more often |
| `cnf` | Confirmation key: SHA-256 thumbprint of the controller's device or per-session key |
| `parent` | Hash of the parent token for delegation chains |

Rules:

- A root grant is issued by the provider-approved user or workspace owner key; delegation narrows from there.
- A delegated chain has a maximum depth of 3 hops: provider-approved root → workspace orchestrator → runtime task.
- Each hop may only narrow `cap_uri`, operations, resource scope and expiry; it cannot widen them.
- `jti` is unique per token and is recorded so a token can be revoked or denied replay independently of its `parent` chain.
- When `cnf` is present, every invocation must carry a proof-of-possession signature from the named key (or a channel binding that proves it). A token presented without the matching key is rejected even if the signature chain is valid.
- `epoch_id` is the display session's `generation`; a token bound to an old generation is rejected at the provider. See `docs/architecture/identifiers-and-counters.md`.
- Effective validity starts at the latest `nbf` and ends at the earliest `exp` across the chain.
- Verification bounds the chain length and total token size before parsing to prevent denial of service.
- Revocation is checked against the latest signed revocation record; stale records fail closed for high-impact capabilities.
- A token does not grant workspace ownership, device trust or capabilities outside its `cap_uri`.

### 5. Invocation is request/response with cancellation

A capability invocation includes:

- request and correlation IDs;
- workspace ID;
- requesting application and instance IDs;
- provider device and session;
- `cap_uri` and version;
- `jti` of the authorizing grant;
- lease reference;
- typed arguments;
- expiry and cancellation token.

The response includes:

- request ID;
- result or typed error;
- resource reference;
- content hash where applicable;
- execution metadata;
- cancellation status.

Streaming capabilities use explicit open, data, close and cancel messages. Cancellation must not leave resources allocated.

### 6. The resolver chooses providers; the caller asks for capabilities

The caller requests a capability, not a device. A `CapabilityResolver` filters providers by:

- capability version;
- authorization;
- availability;
- constraints;
- latency budget;
- execution location.

Provider selection must be deterministic for tests and explainable in diagnostics.

### 7. Capability interfaces evolve independently

Capability versions are negotiated separately from the transport and wire format. A device may support several versions of a capability. Unsupported required versions fail closed with a typed error.

### 8. Device and workspace permissions are not implicit

Connecting a phone does not grant access to its camera roll, microphone, clipboard or filesystem. Pairing establishes identity; it does not establish capability authorization.

### 9. Browser applications are capability consumers

The browser is a first-class consumer of the same model:

- A browser application requesting files receives a scoped file grant.
- A browser application requesting camera receives a scoped camera grant.
- The browser does not receive device-wide filesystem or media authority.
- A browser application cannot self-approve a grant.
- User approval is mediated by the provider device or an explicit workspace prompt.
- A browser application's origin, identity and session are part of the authorization context.

AD-CAP is active in the MVP, not deferred. The initial consumer set is files and camera.

## Consequences

### Positive

- Devices can contribute narrow capabilities without exposing the whole device.
- Permissions, expiry and revocation become testable.
- The workspace can choose compute, display or input providers without device-specific branching.
- Capability contracts can evolve independently of transport.

### Negative

- Adds schema, resolver and audit implementation work.
- Requires explicit UI for permission prompts and revocation.
- Poorly scoped capabilities can still create privacy risk.
- Capability discovery after pairing adds a second negotiation step.

## Acceptance gates

- Descriptor validation rejects unknown required versions and malformed constraints.
- Unauthorized, expired and revoked grants and leases are denied.
- A lease cannot outlive its grant, application instance or workspace authorization.
- A capability request can be authorized, leased and revoked.
- Application context is part of the authorization decision.
- A granted but busy capability is reported as `busy` (or `restricted` where policy limits it), not denied or silently collapsed into `unavailable`.
- Invocation cancellation releases resources and is idempotent.
- Resolver selection is deterministic and explained in diagnostics.
- Pairing alone grants no optional capability or workspace ownership.
- Grant issuance names an authenticated issuer and is signed; the coordinator cannot mint grants.
- Grants are `COSE_Sign1` tokens with `jti`, `cap_uri`, `op`, `nbf`, `exp`, `epoch_id` (session `generation`) and optional `cnf`; delegation depth is ≤3 and each hop only attenuates.
- A token with `cnf` requires proof of possession on invocation; a missing or mismatched key is rejected.
- Availability reports `available`, `busy`, `restricted` or `unavailable`; `restricted` is never collapsed into `busy` or `denied`.
- Expired, revoked and stale-revocation grants are denied; bounded offline windows are explicit.
- Browser files and camera consumers receive scoped grants, not device-wide access.
- `CapabilityResolver` and `ProfileResolver` have separate, documented responsibilities.
- Capability and workspace audit events are recorded locally without sensitive payloads.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Device-wide permissions | Violates least privilege and makes revocation all-or-nothing |
| Central ACL server | Breaks offline use and makes the coordinator an authority |
| Nested-JWT UCAN | Adds DID resolution and per-hop overhead; COSE satisfies the scope |
| Long-lived bearer tokens | Cannot be bounded to a session generation or proof-of-possession |
| Scoped `COSE_Sign1` grants with leases, `jti`, `cnf` and short expiry | Chosen: offline verification, attenuable, revocable and bound to the caller |

## Out of scope

- AI tool discovery and intent planning.
- Multi-user role administration.
- Cross-organization capability federation.
- Automatic installation of third-party capability providers.

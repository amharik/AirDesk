# ADR-012: Capability advertisement, invocation and authorization

- **Status:** Proposed — capability and authorization gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — capability leases and application context added
- **Deciders:** Security owner, engineering lead
- **Scope:** Capability descriptors, leases, grants, invocation, resolution, audit, revocation, application context
- **Supersedes:** None
- **Related:** ADR-001, ADR-005, ADR-008, ADR-010, ADR-011, ADR-013, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018, ADR-019

## Context

`RuntimeCapabilities` is a set of booleans that describes a runtime, not a distributed device fabric. It does not express availability, permission requirements, resource limits, transport, expiry or revocation.

AirDesk needs devices to contribute specific capabilities without granting wholesale access to the device.

## Decision

### 1. Capabilities are versioned interfaces

A capability descriptor contains:

| Field | Purpose |
| --- | --- |
| `capabilityId` | Namespaced identity, for example `media.camera.capture` |
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
| Availability | `available`, `busy`, `unavailable` |
| Authorization | `ungranted`, `granted`, `denied`, `revoked` |

A capability can be available but ungranted. It can be granted but currently unavailable. The UI must not imply that availability is permission.

### 3. Grants are scoped, short-lived and auditable

A grant contains:

- capability ID and version;
- provider device;
- resource scope;
- issuing workspace and user context;
- creation time and expiry;
- grantor;
- audit identifier;
- revocation status.

Do not grant `filesystem.access`. Grant scoped capabilities such as:

- `filesystem.documents.read`;
- `filesystem.documents.write`;
- `media.camera.capture`;
- `clipboard.read`;
- `compute.wasm.execute`.

High-impact capabilities require explicit user approval. Expired, revoked or out-of-scope grants are denied.

### 4. Grant issuance and revocation are explicit

- A grant is issued by the authenticated user context on the granting device or by a local workspace authorization service acting for that user.
- The issuer signs the grant with a grant-signing key bound to the device identity from ADR-011.
- The verifier is the provider device or the provider's local policy engine.
- The coordinator may distribute revocation records but must not mint grants.
- A grant names its issuer, subject device, provider device, scope, expiry and revocation sequence.
- Revocation records are signed and sequence-numbered.
- A provider that cannot obtain a current-enough revocation record fails closed for high-impact capabilities.
- Offline providers may accept a bounded-staleness revocation window; the window is explicit per capability.
- Revocation invalidates new invocations; an in-flight invocation is cancelled unless the capability declares a safe completion path.

### 4.1 Capability leases are the bounded access object

A **capability lease** is the time-bounded authorization a requester holds for a capability. A signed grant records the policy decision; the lease records the active, scoped access.

A lease contains:

- lease ID;
- device and capability IDs;
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

### 5. Invocation is request/response with cancellation

A capability invocation includes:

- request and correlation IDs;
- workspace ID;
- requesting application and instance IDs;
- provider device and session;
- capability ID and version;
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
- A granted but busy capability is reported as unavailable, not denied.
- Invocation cancellation releases resources and is idempotent.
- Resolver selection is deterministic and explained in diagnostics.
- Pairing alone grants no optional capability or workspace ownership.
- Grant issuance names an authenticated issuer and is signed; the coordinator cannot mint grants.
- Expired, revoked and stale-revocation grants are denied; bounded offline windows are explicit.
- Browser files and camera consumers receive scoped grants, not device-wide access.
- `CapabilityResolver` and `ProfileResolver` have separate, documented responsibilities.
- Capability and workspace audit events are recorded locally without sensitive payloads.

## Out of scope

- AI tool discovery and intent planning.
- Multi-user role administration.
- Cross-organization capability federation.
- Automatic installation of third-party capability providers.

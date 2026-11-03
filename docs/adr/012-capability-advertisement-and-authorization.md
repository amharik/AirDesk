# ADR-012: Capability advertisement, invocation and authorization

- **Status:** Proposed — capability and authorization gates required
- **Date:** 2026-11-03
- **Scope:** Capability descriptors, grants, invocation, resolution, audit, revocation
- **Supersedes:** None
- **Related:** ADR-001, ADR-005, ADR-008, ADR-010, ADR-011, ADR-013

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

### 4. Invocation is request/response with cancellation

A capability invocation includes:

- request and correlation IDs;
- workspace and provider device;
- capability ID and version;
- typed arguments;
- grant reference;
- expiry and cancellation token.

The response includes:

- request ID;
- result or typed error;
- resource reference;
- content hash where applicable;
- execution metadata;
- cancellation status.

Streaming capabilities use explicit open, data, close and cancel messages. Cancellation must not leave resources allocated.

### 5. The resolver chooses providers; the caller asks for capabilities

The caller requests a capability, not a device. A `CapabilityResolver` filters providers by:

- capability version;
- authorization;
- availability;
- constraints;
- latency budget;
- execution location.

Provider selection must be deterministic for tests and explainable in diagnostics.

### 6. Capability interfaces evolve independently

Capability versions are negotiated separately from the transport and wire format. A device may support several versions of a capability. Unsupported required versions fail closed with a typed error.

### 7. Device and workspace permissions are not implicit

Connecting a phone does not grant access to its camera roll, microphone, clipboard or filesystem. Pairing establishes identity; it does not establish capability authorization.

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
- Unauthorized, expired and revoked grants are denied.
- A granted but busy capability is reported as unavailable, not denied.
- Invocation cancellation releases resources and is idempotent.
- Resolver selection is deterministic and explained in diagnostics.
- Pairing alone grants no optional capability.
- Capability and workspace audit events are recorded locally without sensitive payloads.

## Out of scope

- AI tool discovery and intent planning.
- Multi-user role administration.
- Cross-organization capability federation.
- Automatic installation of third-party capability providers.

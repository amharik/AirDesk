# ADR-010: AirDesk Fabric Protocol semantic scope and module boundaries

- **Status:** Proposed — specification and conformance gates required
- **Date:** 2026-11-03
- **Scope:** Protocol semantics, module boundaries, versioning, schema evolution, Cast projection
- **Supersedes:** None
- **Related:** ADR-001, ADR-004, ADR-005, ADR-008, ADR-009, ADR-011, ADR-012, ADR-013

## Context

AirDesk needs one logical way for devices to participate in a workspace across different transports. It does not need another transport protocol.

The existing repository already has:

- ADR-001 session/runtime/display separation.
- ADR-005 display profiles, transport framing and Cast messaging.
- ADR-008 canonical input vocabulary.
- A FlatBuffers schema and generated Swift, TypeScript and Rust bindings.

The proposed AirDesk Fabric Protocol (ADFP) is useful only if it extends those decisions rather than creating a parallel stack.

## Decision

### 1. ADFP owns semantics, not networking

ADFP defines workspace and device meaning:

- device identity references;
- session establishment and negotiation;
- capability advertisement, grants and invocation;
- workspace identity and recovery references;
- application and window lifecycle semantics when they enter scope.

ADFP does not define TCP, UDP, TLS, WebRTC, QUIC or a new cryptographic transport.

### 2. Module set is deliberately small

Active modules for the browser-first plan:

| Module | Responsibility | Relationship |
| --- | --- | --- |
| AD-ID | Device identity references and pairing messages | ADR-011 |
| AD-LINK | Session establishment, protocol negotiation, cancellation | ADR-005, ADR-013 |
| AD-CAP | Capability descriptor, grants and invocation | ADR-012 |
| AD-WS | Workspace identity, persistence references and recovery | ADR-009 |
| AD-INPUT | Pointer, keyboard, touch and text input | ADR-008 |
| AD-DISPLAY | Display registration, viewport and profile | ADR-005 |

Future modules, not active:

- AD-APP: application registry and lifecycle.
- AD-WINDOW: window lifecycle and geometry.
- AD-RESOURCE: file, clipboard and resource transfer.
- AD-MEDIA: camera, microphone, audio and video negotiation.
- AD-SYNC: synchronization and conflict handling.
- AD-AI: intent and task execution.
- AD-GROUP: multi-user membership.

A device may implement AD-INPUT and AD-DISPLAY without implementing AD-APP or AD-MEDIA.

### 3. Existing ADRs remain authoritative for their domains

- ADR-005 owns display profiles, transport envelopes and Cast framing.
- ADR-008 owns the input event vocabulary, validation and coalescing.
- ADR-009 owns workspace persistence.
- ADR-013 owns transport sequencing and selection.

ADFP must not duplicate or contradict those decisions.

### 4. FlatBuffers remains the canonical control schema

Do not switch to Protocol Buffers or CBOR now. The existing `protocol/airdesk.fbs` is the source of truth.

The current control message is too loosely typed:

- `appearance`, `message`, `action` and `code` are generic strings.
- There is no request correlation, idempotency, expiry, sender identity or cancellation field.

Evolve the schema in a backward-compatible protocol revision:

- Add a control-plane header with `message_id`, `sender_device_id`, `correlation_id`, `idempotency_key`, `expires_at` and `cancellation_id`.
- Add typed payload tables for identity, pairing, capability, session, workspace, window, resource and error messages.
- Keep high-frequency pointer frames compact; do not add the rich header to every pointer move.
- Preserve the compact Cast JSON profile as a projection with semantic parity tests.
- Keep generated bindings committed and reproducible.

Do not change the schema without conformance fixtures and a migration note.

### 5. Version axes are independent

Track separately:

- Wire-format version.
- Capability-interface version.
- Workspace-manifest version.
- Application-manifest version.
- Discovery protocol version.

A protocol version match is not sufficient. Peers negotiate supported capabilities and fail closed when a required capability or version is absent.

### 6. Request semantics are explicit

Control messages support:

- request/response correlation;
- idempotency keys;
- expiration;
- cancellation;
- bounded message sizes;
- sender identity;
- authorization context;
- typed error codes and retry classification.

Pointer movement may be dropped when stale. Clicks, key releases, text commits and lifecycle transitions must not be silently lost.

### 7. Conformance is a release gate

Maintain shared fixtures across Swift, TypeScript and Rust:

- valid round-trips;
- duplicate messages;
- stale session and generation values;
- malformed and oversized frames;
- cancellation;
- keyboard release and focus loss;
- viewport changes;
- Cast JSON semantic parity.

## Consequences

### Positive

- One semantic protocol can span browser, native, Cast and future host agents.
- Existing input and display work is preserved.
- Transport experiments do not require protocol rewrites.
- Capability and workspace behavior can be tested independently of transport.

### Negative

- Typed payloads require a schema migration and generated-binding updates.
- More control-plane metadata increases validation work.
- The Cast JSON projection can drift from the binary schema without parity tests.

## Acceptance gates

- ADFP 0.1 specification describes active modules and explicit non-goals.
- The envelope and typed control payloads round-trip across Swift, TypeScript and Rust.
- Malformed, oversized, duplicate and stale-generation messages are rejected.
- Cast JSON and FlatBuffers carry equivalent control semantics for supported messages.
- No active module duplicates ADR-005 or ADR-008 ownership.
- A device can participate with a subset of modules.

## Out of scope

- Replacing FlatBuffers with another serialization format.
- Defining a new transport or cryptographic handshake.
- Implementing AD-APP, AD-WINDOW, AD-RESOURCE, AD-MEDIA, AD-SYNC, AD-AI or AD-GROUP in this cycle.
- Making libp2p a required dependency.

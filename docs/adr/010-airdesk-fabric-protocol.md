# ADR-010: AirDesk Fabric Protocol semantic scope and module boundaries

- **Status:** Proposed — specification and conformance gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — major amendment for orchestration, runtime and resource modules
- **Deciders:** Engineering lead, protocol owner
- **Scope:** Protocol semantics, module boundaries, versioning, schema evolution, orchestration and lifecycle messages, Cast projection
- **Supersedes:** None
- **Related:** ADR-001, ADR-004, ADR-005, ADR-008, ADR-009, ADR-011, ADR-012, ADR-013, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018, ADR-019

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

### 2. Module set is deliberately scoped

MVP modules:

| Module | Responsibility | Relationship |
| --- | --- | --- |
| AD-ID | Device identity references and pairing messages | ADR-011 |
| AD-LINK | Session establishment, connectivity and transport negotiation, cancellation | ADR-005, ADR-013 |
| AD-CAP | Capability descriptor, leases and invocation | ADR-012, ADR-018 |
| AD-WS | Workspace identity, desired-state references, reconciliation and recovery | ADR-009, ADR-016, ADR-017 |
| AD-INPUT | Pointer, keyboard, touch, text and controller arbitration | ADR-008, ADR-015 |
| AD-DISPLAY | Display registration, viewport and presentation profile | ADR-005, ADR-014 |
| AD-RUNTIME | Runtime provider lifecycle, execution and observed status | ADR-004, ADR-017 |
| AD-RESOURCE | Resource references, access and transfer | ADR-009, ADR-016 |

Early modules:

- AD-APP: application manifests and lifecycle (ADR-019).
- AD-WINDOW: window metadata and operations.

Later modules:

- AD-MEDIA: camera, microphone, audio and video negotiation.
- AD-SYNC: encrypted synchronization and conflict handling.
- AD-AI: intent and task execution.
- AD-GROUP: multi-user membership and collaboration.

A device may implement AD-INPUT and AD-DISPLAY without implementing AD-APP, AD-RUNTIME or AD-MEDIA. ADFP must not require a device to implement every module.

### 2.1 Orchestration and lifecycle messages

AD-WS and AD-RUNTIME carry semantic messages for:

- workspace open, close, desired-state update and reconciliation;
- application instance desired/observed state;
- runtime create, start, suspend, stop, destroy and status;
- capability lease request, release, expiry and revocation;
- resource reference resolution and access denial;
- placement request and placement result;
- recovery and unavailable-state reporting.

These messages describe intent and observed results. They do not make the coordinator, display endpoint or runtime provider the workspace authority.

### 3. Existing ADRs remain authoritative for their domains

- ADR-005 owns display profiles, transport envelopes and Cast framing.
- ADR-008 owns the input event vocabulary, validation and coalescing.
- ADR-009 owns workspace persistence.
- ADR-013 owns transport sequencing and selection.
- ADR-014 owns browser endpoint topology.
- ADR-015 owns session ownership, cursors and keyboard focus.

AD-CAP is active, not speculative. The browser applications are concrete consumers: files and camera use scoped grants, not device-wide permissions.

`ProfileResolver` (ADR-001) chooses a display/runtime profile. `CapabilityResolver` (ADR-012) chooses a capability provider. They are separate resolvers; AD-CAP supplies the provider facts both consume.

ADFP must not duplicate or contradict those decisions.

### 4. Session ownership is explicit

- AD-LINK is the canonical ADFP session-establishment vocabulary.
- AD-ID supplies device identity and pairing.
- ADR-011 supplies session credentials.
- ADR-015 owns cursor, focus and multi-controller arbitration.
- ADR-001's Cast v2 handshake is a transport-specific legacy handshake.
- AD-LINK must state whether it wraps or subsumes Cast v2; it may not introduce a second incompatible session model.

### 5. FlatBuffers remains the canonical control schema

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

### 6. Version axes are independent

Track separately:

- Wire-format version.
- Capability-interface version.
- Workspace-manifest version.
- Application-manifest version.
- Discovery protocol version.
- Transport binding and transport protocol version, including WebTransport's evolving wire format.

A protocol version match is not sufficient. Peers negotiate supported capabilities and fail closed when a required capability or version is absent. AD-LINK negotiation must distinguish ADFP semantic compatibility from transport compatibility.

### 7. Request semantics are explicit

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

### 8. Conformance is a release gate

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
- The envelope and typed control payloads round-trip across Swift and TypeScript; Rust round-trip is qualified only when a Rust host is in scope.
- Malformed, oversized, duplicate and stale-generation messages are rejected.
- Cast JSON and FlatBuffers carry equivalent control semantics for supported messages.
- No active module duplicates ADR-005, ADR-008, ADR-014, ADR-015, ADR-016 or ADR-017 ownership.
- A device can participate with a subset of modules.
- AD-LINK, ADR-001, ADR-011 and ADR-015 use one session vocabulary; the Cast v2 relationship is stated.
- AD-WS and AD-RUNTIME can express workspace desired state, placement and observed runtime status without transferring workspace authority.
- AD-CAP can express a scoped lease, expiry and revocation.
- AD-RESOURCE can resolve a resource reference and report access denial without embedding a provider-local path.
- Lifecycle messages are idempotent and correlated.

## Out of scope

- Replacing FlatBuffers with another serialization format.
- Defining a new transport or cryptographic handshake.
- Implementing AD-APP, AD-WINDOW, AD-MEDIA, AD-SYNC, AD-AI or AD-GROUP in this cycle.
- Making libp2p a required dependency.

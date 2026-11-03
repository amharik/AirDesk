# ADR-014: Browser endpoint topology and host service

- **Status:** Proposed — endpoint and host-service qualification required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — browser re-scoped as a presentation endpoint; local agent is not workspace authority
- **Deciders:** Product owner, engineering lead, security owner
- **Scope:** Browser endpoint, local host service, coordinator, certificates, browser identity storage, presentation authority
- **Supersedes:** None
- **Amends:** ADR-001, ADR-005, ADR-013
- **Related:** ADR-004, ADR-009, ADR-011, ADR-012, ADR-015, ADR-016, ADR-017, ADR-018

## Context

AirDesk needs a browser endpoint that can present a workspace on a machine without installing a native receiver UI. A browser cannot accept arbitrary inbound connections, cannot scan its own QR code usefully, and cannot be an always-on workspace server. An iOS app cannot remain an always-on listener while suspended.

The revised blueprint changes the browser's role:

- a browser is a display endpoint, not the canonical workspace owner;
- a local agent is a host service that exposes the endpoint and participates in the device fabric;
- the workspace remains independent of both, per ADR-016;
- the browser endpoint follows the personal device fabric, not the first workspace release.

## Decision

### 1. Browser endpoint topology

```text
Controller devices (iPhone / iPad / other agents)
        |
        |  identity, presence, pairing and signaling
        v
  AirDesk coordinator
        |
        |  registry, signaling, signed revocation
        v
Local AirDesk host agent
        |
        |  loopback browser session
        v
Browser presentation endpoint
```

- A local host agent runs on the machine that provides the browser endpoint.
- The agent serves the browser shell and desktop assets over loopback.
- The agent participates in the device fabric as a host, not as the workspace owner.
- Controllers pair through the coordinator or a QR bootstrap.
- Direct data is preferred; coordinator relay is post-MVP.
- The browser renders a display session supplied by the host agent and orchestrator.

### 2. Browser and agent do not own the workspace

- Workspace identity and desired state are defined by ADR-016.
- The browser is a presentation consumer and may persist presentation preferences locally.
- The local agent may host a runtime provider and local resources; it does not own workspace identity.
- A browser reload, reload failure or endpoint replacement does not create or delete the workspace.
- A host agent failure makes the endpoint unavailable; it does not delete the workspace.
- The coordinator is never the workspace authority.

### 3. The browser loads first-party local code only

In the MVP browser-endpoint release:

- the browser shell is served by the local host agent;
- the loopback origin is the only origin trusted to load executable shell assets;
- the browser-facing asset server binds to loopback only;
- the agent's authenticated controller listener may bind to LAN interfaces, but it does not serve browser assets there;
- loopback HTTP is acceptable only when isolation headers, Host/Origin checks and a per-session token are enforced; otherwise the agent uses locally trusted TLS.

A future hosted endpoint is a separate decision and requires:

- a first-party hosted origin;
- version pinning and SRI for executable assets;
- a strict CSP;
- a documented update and revocation process;
- a pairing-key threat model for a remote-origin page.

A hosted endpoint still does not become the workspace authority.

### 4. Coordinator responsibility remains narrow

The coordinator provides:

- device registration and presence;
- pairing/signaling exchange;
- short-lived session coordination;
- signed revocation distribution;
- optional connection hints.

The coordinator must not:

- receive workspace contents or terminal output;
- receive long-lived private keys;
- mint capability grants or leases;
- own workspace identity or desired state;
- become the data-plane relay in the MVP.

A coordinator compromise must not expose workspace files or device private keys. It may expose metadata and availability.

### 5. Browser identity is explicit and recoverable

- Ed25519 is the default identity algorithm where WebCrypto support exists.
- P-256 is the fallback where Ed25519 is unavailable.
- Browser private keys are non-extractable where supported and are stored in IndexedDB or OPFS.
- If browser storage is evicted, the browser identity is lost. The user must re-pair; the app must not silently rotate identity.
- A browser identity is device/browser-profile scoped, not an account or workspace identity.
- A lost browser identity does not revoke other devices or grant access to workspace state.

### 6. Display sessions are temporary presentations

- A workspace may have zero, one or many display sessions.
- Each browser endpoint creates a display session for a workspace.
- The display session stores presentation state, viewport, focus and controller attachments.
- Window layout preferences may be persisted by the workspace; transient display state is session-scoped.
- Multiple controllers may attach under ADR-015.
- A display session cannot write canonical workspace state.

### 7. Certificates and secure context

- Loopback sessions use loopback trust rules and enforce Host/Origin checks and isolation headers.
- Coordinator connections use HTTPS/WSS with a publicly trusted certificate.
- Direct peer connections use authenticated TLS 1.3 or DTLS.
- There is no plaintext LAN fallback.
- A LAN-reachable browser asset server requires a separately documented certificate model and is not part of the MVP.
- The agent's LAN controller listener is authenticated and encrypted; it is not a browser asset origin.

### 8. Threat boundaries are explicit

The local agent, coordinator and browser endpoint add trust boundaries:

- compromised local agent;
- compromised coordinator;
- malicious browser origin;
- QR replay or session fixation;
- stale or revoked device;
- untrusted display metadata;
- browser storage eviction;
- coordinator metadata correlation;
- browser endpoint attempting to act as workspace authority.

SEC-04 must cover these before the browser endpoint is qualified.

## Consequences

### Positive

- The browser endpoint avoids remote-origin executable code.
- The topology respects iOS suspension and browser inbound restrictions.
- The workspace remains independent of the endpoint and host service.
- The coordinator remains a control plane, not a content or workspace authority.
- Multiple controllers can attach without transferring workspace ownership.

### Negative

- The browser endpoint requires a local host agent; it is not zero-install.
- A coordinator service is required for pairing and presence.
- Browser identity can be lost with storage eviction and requires re-pairing.
- Multi-controller behavior still requires ADR-015 arbitration.
- Relay and cross-network operation are deferred.

## Acceptance gates

- A browser loads the shell from the local host agent over loopback with isolation headers and no remote executable assets.
- The browser endpoint can present and reconnect a workspace without becoming its authority.
- A host-agent failure leaves the workspace definition intact.
- Controllers pair through the coordinator or QR bootstrap.
- Direct data works when connectivity allows; no relay is silently used.
- Coordinator compromise cannot expose workspace content, terminal output or device private keys.
- Browser identity eviction produces a re-pair flow, not a silent identity change.
- Two controllers attach with distinct cursors and explicit keyboard focus.
- No plaintext LAN transport exists.
- SEC-04 covers agent, coordinator, browser origin, pairing and revocation.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Hosted receiver as workspace host | Remote-origin executable code, pairing-key exposure and workspace authority in the wrong place |
| Phone-hosted LAN HTTPS | iOS suspension, local-network permission, certificate trust and unstable availability |
| Localhost-only agent | No multi-device registry or coordinator; insufficient for the device fabric |
| Browser as canonical workspace host | Violates workspace independence and makes presentation state authoritative |

## Out of scope

- Hosted browser endpoint as workspace host.
- Coordinator-owned workspace content.
- Cross-device state synchronization.
- Relay/TURN implementation and pricing.
- Android TV or native TV endpoints.

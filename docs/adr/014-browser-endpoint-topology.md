# ADR-014: Browser endpoint topology, local agent and trust boundaries

- **Status:** Proposed — agent, coordinator and browser qualification required
- **Date:** 2026-11-03
- **Deciders:** Product owner, engineering lead, security owner
- **Scope:** Browser-first endpoint topology, local agent, coordinator, certificates, browser identity storage, workspace authority
- **Supersedes:** None
- **Related:** ADR-001, ADR-004, ADR-005, ADR-009, ADR-011, ADR-013, ADR-015

## Context

The browser-first plan needs a concrete connection topology. A browser cannot accept arbitrary inbound connections, cannot scan its own QR code usefully, and cannot be an always-on workspace server. An iOS app cannot remain an always-on listener while suspended.

The previous plan left open:

- who listens;
- where the browser receiver is served from;
- how local certificates are trusted;
- where the browser identity is stored;
- who owns browser workspace state;
- how multiple devices attach to one display.

A hosted receiver page would solve some distribution issues, but it introduces remote-origin executable code, hosting cost and a new trust boundary. That conflicts with the existing offline-runtime and no-remote-code decisions.

## Decision

### 1. MVP topology is local agent + coordinator + direct data

```text
Controller devices (iPhone / iPad)
        |
        |  pairing and presence via coordinator
        v
  AirDesk coordinator
        |
        |  signaling, registry, revocation
        v
Local AirDesk agent on the display machine
        |
        |  loopback browser session
        v
Browser receiver page
```

- A local AirDesk agent runs on the machine that owns the display.
- The agent serves the browser receiver and desktop assets to the browser over loopback.
- The agent registers with the coordinator.
- Controllers pair through the coordinator or a QR bootstrap.
- Data is carried directly between agents/devices when possible.
- Coordinator relay is a fallback, not the default data path, and is not implemented in this cycle.

The MVP is therefore **browser-surface-first with a local agent**, not zero-install.

### 2. The browser loads first-party local code only

In the MVP:

- The browser receiver is served by the local agent.
- The browser does not load the desktop shell from a remote origin.
- The loopback origin is the only origin trusted to load the shell.
- The browser-facing asset server binds only to loopback.
- The agent's authenticated controller listener may bind to LAN interfaces; it does not serve browser assets there.
- Loopback HTTP is acceptable for local secure-context purposes only if isolation headers and origin checks are enforced; otherwise the agent uses locally trusted TLS.

A future hosted receiver is a separate decision and requires:

- a first-party hosted origin;
- version pinning and SRI for executable assets;
- a strict CSP;
- a documented update and revocation process;
- an explicit threat model for pairing keys in a remote-origin page.

### 3. Coordinator responsibility is narrow

The coordinator provides:

- device registration and presence;
- pairing/signaling exchange;
- short-lived session coordination;
- signed revocation distribution;
- optional connection hints.

The coordinator must not:

- receive workspace contents or terminal output;
- receive long-lived private keys;
- mint capability grants;
- become the workspace authority in the MVP.

A coordinator compromise must not expose workspace files or device private keys. It may expose metadata and availability.

### 4. Browser identity is explicit and recoverable

- Ed25519 is the default identity algorithm where WebCrypto support exists.
- P-256 is the fallback where Ed25519 is unavailable.
- Browser private keys are non-extractable where the browser supports it and are stored in IndexedDB or OPFS.
- If browser storage is evicted, the browser identity is lost. The user must re-pair; the app must not silently rotate identity.
- A browser identity is device/browser-profile scoped, not an account identity.
- A lost browser identity does not revoke other devices or grant access to native workspace state.

### 5. Workspace authority is device-local

For the MVP:

- Each device owns its local workspace and resource state.
- The browser keeps an aggregate session for display, input and connected-device presentation.
- The aggregate session is not a replica of every device's workspace.
- The browser may persist display layout locally, but it is not authoritative for another device's files or application state.
- Cross-device workspace synchronization is future work owned by ADR-009 and a future synchronization ADR, not this ADR.

A coordinator-owned session metadata layer may be added later. It does not make the coordinator the authority for device content.

### 6. Multiple devices can attach to one display

- Multiple controllers may attach to one browser display session.
- Each controller has its own cursor identity, color and label.
- Multi-controller input is the default.
- Keyboard/text focus is owned by one controller at a time with explicit handoff, as defined in ADR-015.
- The display aggregates sessions but does not merge the devices' local storage.

### 7. Certificates and secure context

- Loopback sessions use loopback trust rules and must enforce Host/Origin checks and isolation headers.
- Coordinator connections use HTTPS/WSS with a publicly trusted certificate.
- Direct peer connections use TLS 1.3 or DTLS and authenticated device identities.
- There is no plaintext LAN fallback.
- A LAN reachable browser asset server requires a separately documented certificate provisioning model and is not part of the MVP.
- The agent's LAN controller listener is authenticated and encrypted; it is not a browser asset origin.

### 8. Threat model is part of the design

The local agent and coordinator add trust boundaries:

- compromised local agent;
- compromised coordinator;
- malicious browser origin;
- QR replay or session fixation;
- stale or revoked device;
- untrusted display metadata;
- browser storage eviction;
- coordinator metadata correlation.

SEC-04 must cover these before the browser endpoint is qualified.

## Consequences

### Positive

- The browser endpoint avoids remote-origin executable code.
- The topology respects iOS suspension and browser inbound restrictions.
- The coordinator remains a control plane, not a content authority.
- Device-local ownership avoids premature distributed-state complexity.
- Multi-device display sessions have a clear attachment model.

### Negative

- The MVP requires a local agent install; it is not zero-install.
- A coordinator service is required for pairing and presence.
- Browser identity can be lost with storage eviction and requires re-pairing.
- Multi-controller behavior requires cursor, focus and arbitration work in ADR-015.
- Relay economics and cross-network operation are deferred.

## Acceptance gates

- A browser loads the receiver from the local agent over loopback with isolation headers and no remote executable assets.
- Controllers pair through the coordinator or QR bootstrap.
- Direct data works when connectivity allows; coordinator fallback is explicit and not silently used.
- Coordinator compromise cannot expose workspace content, terminal output or device private keys.
- Browser identity eviction produces a re-pair flow, not a silent identity change.
- Two controllers attach to one browser display with distinct cursors and explicit keyboard focus.
- No plaintext LAN transport exists.
- SEC-04 covers agent, coordinator, browser origin, pairing and revocation.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Hosted receiver page | Remote-origin executable code, pairing-key exposure, hosting cost and a new trust boundary |
| Phone-hosted LAN HTTPS | iOS suspension, local-network permission, certificate trust and unstable availability |
| Localhost-only agent | No multi-device registry or coordinator; insufficient for the chosen multi-device model |
| Pure peer mesh without coordinator | Harder pairing, presence and revocation across networks |

## Out of scope

- Hosted browser receiver.
- Coordinator-owned workspace content.
- Cross-device state synchronization.
- Relay/TURN implementation and pricing.
- Android, desktop host agents or TV-native endpoints.

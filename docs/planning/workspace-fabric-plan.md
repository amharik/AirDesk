# AirDesk Workspace Fabric Plan

- **Status:** Proposed — implementation has not started
- **Date:** 2026-11-03
- **Scope:** Product positioning, MVP endpoint, local agent and coordinator, workspace durability, protocol and capability foundation, release gates
- **Related:** ADR-001 through ADR-015

## 1. Decision summary

| Area | Decision |
| --- | --- |
| Product | Universal personal workspace fabric, not a DeX clone or remote-desktop client |
| MVP endpoint | Browser surface served by a local AirDesk agent; coordinator for registry/pairing; direct data; relay later |
| Later endpoints | USB-C/HDMI/AirPlay/Cast and other qualified open protocols |
| Local runtime | Wanix, with the existing desktop shell and native controller |
| Puter | Remove entirely from production code and product choices |
| Workspace | Device-local state owns the workspace; browser keeps an aggregate session with truthful recovery |
| Protocol | AirDesk Fabric Protocol (ADFP) as a semantic layer over established transports |
| Identity and pairing | Ed25519 default with P-256 fallback, QR pairing, optional native discovery |
| Capabilities | Full scoped, revocable AD-CAP model; browser files and camera are consumers |
| Multi-controller | Multi-pointer default; one keyboard focus owner with explicit handoff |
| Transport | Loopback + WebSocket/TLS control; WebRTC/QUIC direct data; relay post-MVP |
| License | Open business decision; required before SDK or ecosystem publication |

These decisions are implemented through ADR-009 through ADR-015. All seven ADRs are **Proposed** until their acceptance gates pass.

## 2. MVP definition

The first commercial workflow is:

1. A user opens AirDesk on an iPhone or iPad.
2. A local AirDesk agent runs on the display machine, registers with the coordinator and serves the browser receiver over loopback.
3. The user pairs the phone through the coordinator or a QR bootstrap.
4. The browser opens the workspace; the phone becomes a context-aware controller for pointer, keyboard and terminal input.
5. A second controller can attach with its own cursor while one controller owns keyboard focus.
6. The user disconnects, reloads or moves to another supported workspace view.
7. The committed device-local workspace layout, preferences and application state are recovered truthfully.

The browser is the first endpoint because it avoids a native receiver install on the display machine. It is not zero-install: the local agent is required. USB-C, HDMI, AirPlay, Cast and other protocols follow after the browser path is qualified. Cast remains development-only until physical hardware qualification.

### Non-goals for this plan

- Replacing iOS, Android, macOS, Windows or Linux.
- Full desktop video streaming as the default path.
- Native application compatibility across every operating system.
- Multi-user or shared workspaces.
- Hosted browser receiver or remote-origin executable assets.
- Coordinator-owned workspace content.
- Relay or TURN in the MVP.
- Cross-device workspace synchronization.
- Autonomous AI agents or background task execution.
- CRDT synchronization for all workspace state.
- libp2p or WebTransport as mandatory dependencies.
- Production Cast qualification without hardware.

## 3. Workstreams

### Cycle 1: Trusted workspace foundation — weeks 1–6

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| GOV-01 | Approve product and architecture baseline | 2 | — | One approved strategy, architecture baseline and non-goals document |
| GOV-02 | Add ADR index and truthful status fields | 1 | — | Decision status separated from implementation status; no ADR promoted without gates |
| GOV-03 | Publish release-gate matrix and measurement definitions | 2 | GOV-01 | Supported combinations and measurement methods documented |
| SEC-01 | Remove or redact sensitive input logging | 2 | — | No typed text, bridge payloads or JavaScript content in release logs |
| SEC-02 | Enforce strict origin matching | 1.5 | — | Exact scheme/host/port checks at all call sites and tests |
| SEC-03 | Harden the local asset server | 2.5 | — | Host/Origin validation, request bounds, symlink containment and per-session token |
| SEC-04 | Write the threat model | 3 | GOV-03 | Covers local agent, coordinator, browser origin, asset server, pairing, manifests, grants and SDK boundaries |
| CI-01 | Enforce protocol generation in CI | 2 | — | Generated bindings must match the schema; `flatc` version pinned |
| CI-02 | Add protocol conformance tests | 2 | CI-01 | Swift and TypeScript fixtures round-trip; Rust only when a Rust host is in scope; malformed frames rejected |
| CI-03 | Add protocol and third-party paths to workflows | 0.5 | CI-01 | Relevant changes trigger protocol and dependency checks |
| CI-04 | Add SBOM and dependency checks to release | 2 | — | SBOM is generated and verified as a release artifact |
| WS-01 | Approve ADR-009 | 2 | GOV-03 | Manifest, storage contract, migration and recovery semantics approved |
| WS-02 | Implement workspace manifest and store contract | 4 | WS-01 | Versioned manifest, atomic write and backend-neutral store interface |
| WS-03 | Integrate restore into session lifecycle | 4 | WS-02 | Last workspace restored; `.default` only on first run; durable checkpoint used |
| WS-04 | Persist logical window layout | 3 | WS-02 | Identity, bounds, display, state and focus order restored without DOM state |
| WS-05 | Add recovery test suite | 3 | WS-03, WS-04 | Kill/relaunch, disconnect, corruption, migration, disk-full and atomic-write tests |
| UX-01 | Add restore report | 2 | WS-03 | UI states what was restored, restarted, reattached or lost |
| A11Y-01 | Accessibility baseline | 3 | GOV-01 | VoiceOver, keyboard focus, Dynamic Type, reduced motion and IME text commit |
| PUTER-01 | Remove Puter entirely | 3 | — | Adapter, enum, UI, labels, Pro copy and tests removed; build and tests pass |
| PROTO-01 | Approve ADR-010 through ADR-015 | 5 | GOV-02 | All six ADRs reviewed and marked Proposed with gates |
| PROTO-02 | Schema gap analysis for typed control payloads | 2 | CI-02 | Migration path documented; no schema cutover in this cycle |

**Cycle 1 exit gate:** No release path logs user input; protocol generation and conformance are enforced; Puter is gone; native committed workspace state survives supported failures; use cases restore truthfully.

### Cycle 2: Local agent, coordinator and pairing — weeks 7–14

Estimates are engineer-days (ED), not elapsed calendar days.

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| END-01 | Browser endpoint feasibility spike | 5 | GOV-03 | Prove or disprove loopback hosting, COOP/COEP, secure context, asset isolation and QR bootstrap |
| ID-01 | Device identity and QR pairing v1 | 6 | ADR-011 | Ed25519 default, P-256 fallback, nonce/expiry, mutual authentication and replay rejection |
| COORD-01 | Coordinator MVP | 8 | ID-01, ADR-014 | Registration, presence, pairing/signaling and signed revocation distribution; no content or key access |
| AGENT-01 | Local agent bootstrap | 7 | END-01, COORD-01 | Serves receiver over loopback, registers with coordinator and establishes direct signaling |
| END-02 | Browser receiver MVP | 10 | END-01, ID-01, AGENT-01, COORD-01 | One browser endpoint opens, pairs, renders the workspace and recovers committed state |
| MC-01 | Multi-controller cursors and focus | 5 | END-02, ADR-015 | Two controllers show distinct cursors; one owns keyboard focus with explicit handoff |
| CAP-01 | Capability registry v1 | 4 | ADR-012 | Descriptor validation, availability and authorization are separate |
| CAP-02 | Scoped grants and revocation | 4 | CAP-01, COORD-01 | Expiry, audit, signed revocation and lost-device flow work; coordinator cannot mint grants |
| DISC-01 | Native discovery adapter spike | 2 | ID-01 | Bonjour/DNS-SD tested without leaking secrets or capabilities |
| XPORT-01 | Direct transport benchmark | 4 | END-02 | WebRTC/QUIC versus WebSocket p50/p95 latency, CPU, reconnect and browser compatibility measured |
| XPORT-02 | Qualify direct transport | 2 | XPORT-01 | ADR-013 updated with evidence; relay remains post-MVP |
| A11Y-02 | Full accessibility audit | 5 | A11Y-01 | VoiceOver, keyboard-only, switch control, RTL and localization checks |
| OBS-01 | End-to-end measurement instrumentation | 3 | END-02 | Ack latency, frame latency, startup, reconnect and crash-free sessions separated |
| BETA-01 | Private beta readiness | 5 | All above | Onboarding, diagnostics, privacy policy and known limitations ready |

**Cycle 2 exit gate:** A local agent plus coordinator delivers a browser workspace without technical assistance; pairing is secure and revocable; direct data works and relay is absent; multiple controllers attach with explicit keyboard focus.

### Later work

- USB-C/HDMI/AirPlay qualification and parity.
- Cast hardware qualification, if hardware is available.
- Hosted browser receiver with a first-party origin and pinned assets.
- Relay/TURN fallback and coordinator-owned session metadata.
- Android companion.
- macOS, Windows and Linux host agents.
- Xpra, RDP RAIL and ScreenCaptureKit remoting.
- Shared workspaces, synchronization and CRDTs for documents.
- Intent-based interaction with approval gates.

## 4. Release gates

| Gate | Exit criteria |
| --- | --- |
| G0: Privacy and CI | No sensitive release logging; strict origins; protocol generation and conformance pass; SBOM produced |
| G1: Workspace durability | Native committed workspace state survives relaunch, disconnect, corruption and migration; browser/in-flight limits are reported; restore report is truthful |
| G2: Browser endpoint | Local agent serves the receiver; coordinator pairs the device; direct data works; workspace recovers; relay is absent |
| G3: Identity and pairing | AD-PAIR-1 rejects replay, expiry, transcript mismatch and bad signatures; devices can be revoked; discovery leaks no secrets |
| G4: Capabilities | Unauthorized, expired and revoked grants are denied; grant issuance is signed; capability invocation is auditable |
| G5: Transport | A direct path meets the latency budget; relay is not used; any transport change is selected only after benchmark |
| G6: Accessibility | VoiceOver, keyboard-only, Dynamic Type, reduced motion and IME pass the supported matrix |
| G7: Multi-controller | Distinct cursors, single keyboard focus, explicit handoff, no stuck input and revocation enforcement |

### Measurement definitions

- **Input acknowledgement latency:** controller dispatch to bridge acknowledgement.
- **Input-to-frame latency:** controller dispatch to display-side frame application time.
- **Warm restore:** process start to a usable restored workspace.
- **Committed-state loss:** loss of state that was already acknowledged as saved by the native store. In-flight writes and browser storage eviction are excluded from the zero-loss claim and must be reported.
- **Stuck input:** a pressed key or button that remains pressed after disconnect, focus loss, generation change or cancellation.
- **Direct path:** browser/controller to local agent without a coordinator or relay carrying workspace data.
- **Pairing success:** completion of AD-PAIR-1 with transcript verification and an issued session credential.

Targets are qualification hypotheses, not current measurements. Do not claim p95 results without a recorded scenario, device matrix and measurement method.

## 5. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Local agent install makes onboarding too heavy | Feasibility spike before MVP commitment; keep agent install small; fall back to external display |
| Browser receiver cannot run Wanix without isolation headers | Feasibility spike before MVP commitment; fall back to external display |
| Coordinator compromise exposes content or keys | Coordinator carries no workspace data, no private keys and no grant minting; SEC-04 covers it |
| Coordinator availability blocks pairing | Short-lived pairing and presence only; explicit diagnostics; relay and hosted fallback are post-MVP |
| QR pairing scope expands into a full identity system | Local device identity and grants only; no account login in v1 |
| Workspace scope grows into sync and CRDTs | ADR-009 limits v1 to device-local persistence and truthful recovery |
| Protocol redesign destabilizes existing input | Extend ADR-008/FlatBuffers incrementally; conformance tests before migration |
| Cast or hardware qualification blocks release | Cast remains development-only until hardware is available |
| Direct transport work delays the browser endpoint | Use the loopback/WebSocket path to make the endpoint usable; add direct WebRTC/QUIC before beta |
| Relay is assumed to be free or private | Relay is post-MVP; no free-tier promise without measured economics and privacy review |
| Multi-controller input conflicts | ADR-015: multi-pointer, single keyboard owner, explicit handoff and stuck-input cleanup |
| Puter removal breaks runtime routing | Remove as one isolated change with build and test coverage |
| Accessibility deferred until after beta | Baseline in Cycle 1; full audit in Cycle 2 |

## 6. Definition of done

Every task must include:

- Code and automated tests.
- Relevant ADR or documentation update.
- CI enforcement where applicable.
- No release logging of user input.
- Migration, rollback or feature-flag behavior.
- Manual verification on the supported matrix.
- An explicit statement of what is not supported.

## 7. First sprint commitment

1. GOV-01, GOV-02, GOV-03.
2. SEC-01, SEC-02, SEC-03.
3. CI-01, CI-03.
4. PROTO-01: approve ADR-010 through ADR-015.
5. Start WS-01 and PUTER-01.

Do not start the browser receiver implementation before END-01 resolves loopback hosting, isolation, secure-context, asset isolation and QR bootstrap questions. Do not start the coordinator implementation before ADR-014 is approved.

## 8. ADR map

| ADR | Decision | Status |
| --- | --- | --- |
| ADR-001 | Multi-runtime architecture | Accepted |
| ADR-002 | Gesture libraries and TypeScript | Accepted |
| ADR-003 | Dependency admission and licensing | Proposed |
| ADR-004 | Runtime and execution baseline | Proposed |
| ADR-005 | Display and transport | Proposed |
| ADR-006 | Remote windowing | Proposed — post-MVP |
| ADR-007 | WinBox and WTerm | Proposed |
| ADR-008 | Input and control protocol | Proposed |
| ADR-009 | Workspace persistence and recovery | Proposed |
| ADR-010 | ADFP semantic scope and module boundaries | Proposed |
| ADR-011 | Device identity, discovery and secure pairing | Proposed |
| ADR-012 | Capability advertisement and authorization | Proposed |
| ADR-013 | Multi-transport and connectivity negotiation | Proposed |
| ADR-014 | Browser endpoint topology | Proposed |
| ADR-015 | Session ownership and multi-controller | Proposed |

The ADR index in `docs/adr/README.md` is authoritative for decision status, implementation status and amendments.

## 9. Open business decision

The repository license is not decided by this plan. No SDK, reference receiver or host-agent publication should occur until the license, contribution model and trademark policy are chosen.

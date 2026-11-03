# AirDesk Workspace Fabric Plan

- **Status:** Proposed — implementation has not started
- **Date:** 2026-11-03
- **Scope:** Product positioning, MVP endpoint, workspace durability, protocol and capability foundation, release gates
- **Related:** ADR-001 through ADR-013

## 1. Decision summary

| Area | Decision |
| --- | --- |
| Product | Universal personal workspace fabric, not a DeX clone or remote-desktop client |
| MVP endpoint | Browser-first presentation, with a timeboxed feasibility spike |
| Later endpoints | USB-C/HDMI/AirPlay/Cast and other qualified open protocols |
| Local runtime | Wanix, with the existing desktop shell and native controller |
| Puter | Remove entirely from production code and product choices |
| Workspace | Runtime-independent manifest with local durability and truthful recovery |
| Protocol | AirDesk Fabric Protocol (ADFP) as a semantic layer over established transports |
| Identity and pairing | Cryptographic device identity, QR pairing, optional native discovery |
| Capabilities | Scoped, revocable grants; availability separate from authorization |
| Transport | WebSocket/TLS baseline; WebRTC, WebTransport and QUIC only after measured qualification |
| License | Open business decision; required before SDK or ecosystem publication |

These decisions are implemented through ADR-009 through ADR-013. All five ADRs are **Proposed** until their acceptance gates pass.

## 2. MVP definition

The first commercial workflow is:

1. A user opens AirDesk on an iPhone or iPad.
2. AirDesk discovers a compatible browser endpoint or displays a pairing QR code.
3. The user pairs and opens a persistent workspace in the browser.
4. The phone becomes a context-aware controller for pointer, keyboard and terminal input.
5. The user disconnects, reloads or moves to another supported workspace view.
6. The committed workspace layout, preferences and application state are recovered truthfully.

The browser is the first endpoint because it is the only zero-install distribution path. USB-C, HDMI, AirPlay, Cast and other protocols follow after the browser path is qualified. Cast remains development-only until physical hardware qualification.

### Non-goals for this plan

- Replacing iOS, Android, macOS, Windows or Linux.
- Full desktop video streaming as the default path.
- Native application compatibility across every operating system.
- Multi-user or shared workspaces.
- Autonomous AI agents or background task execution.
- CRDT synchronization for all workspace state.
- libp2p, QUIC or WebTransport as mandatory dependencies.
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
| SEC-04 | Write the threat model | 2 | GOV-03 | Covers asset server, pairing, manifests, grants, remote content and SDK boundaries |
| CI-01 | Enforce protocol generation in CI | 2 | — | Generated bindings must match the schema; `flatc` version pinned |
| CI-02 | Add protocol conformance tests | 2 | CI-01 | Swift, TypeScript and Rust fixtures round-trip; malformed frames rejected |
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
| PROTO-01 | Approve ADR-010 through ADR-013 | 4 | GOV-02 | All four ADRs reviewed and marked Proposed with gates |
| PROTO-02 | Schema gap analysis for typed control payloads | 2 | CI-02 | Migration path documented; no schema cutover in this cycle |

**Cycle 1 exit gate:** No release path logs user input; protocol generation and conformance are enforced; Puter is gone; committed workspace state survives supported failures; use cases restore truthfully.

### Cycle 2: Browser endpoint and pairing — weeks 7–12

| ID | Task | Est. | Depends | Acceptance |
| --- | --- | ---: | --- | --- |
| END-01 | Browser receiver feasibility spike | 5 | GOV-03 | Prove or disprove COOP/COEP, secure context, asset hosting, discovery and QR bootstrap |
| END-02 | Browser receiver MVP | 12 | END-01 | One browser endpoint opens, pairs, renders the workspace and recovers committed state |
| CAP-01 | Capability registry v1 | 4 | ADR-012 | Descriptor validation, availability and authorization are separate |
| CAP-02 | Scoped grants and revocation | 4 | CAP-01 | Expiry, audit, revocation and lost-device flow work |
| ID-01 | Device identity and QR pairing v1 | 6 | ADR-011 | Ed25519 identity, nonce/expiry, mutual authentication and replay rejection |
| DISC-01 | Native discovery adapter spike | 2 | ID-01 | Bonjour/DNS-SD tested without leaking secrets or capabilities |
| XPORT-01 | WebSocket versus WebRTC benchmark | 4 | END-01 | p50/p95 latency, CPU, reconnect and browser compatibility measured |
| XPORT-02 | Select second transport | 2 | XPORT-01 | ADR-013 updated with evidence; other transports remain adapters |
| A11Y-02 | Full accessibility audit | 5 | A11Y-01 | VoiceOver, keyboard-only, switch control, RTL and localization checks |
| OBS-01 | End-to-end measurement instrumentation | 3 | END-02 | Ack latency, frame latency, startup, reconnect and crash-free sessions separated |
| BETA-01 | Private beta readiness | 5 | All above | Onboarding, diagnostics, privacy policy and known limitations ready |

**Cycle 2 exit gate:** One browser-to-workspace path works without technical assistance; pairing is secure and revocable; one additional transport is chosen by evidence, not assumption.

### Later work

- USB-C/HDMI/AirPlay qualification and parity.
- Cast hardware qualification, if hardware is available.
- Android companion.
- macOS, Windows and Linux host agents.
- Xpra, RDP RAIL and ScreenCaptureKit remoting.
- Shared workspaces, synchronization and CRDTs for documents.
- Intent-based interaction with approval gates.

## 4. Release gates

| Gate | Exit criteria |
| --- | --- |
| G0: Privacy and CI | No sensitive release logging; strict origins; protocol generation and conformance pass; SBOM produced |
| G1: Workspace durability | Committed workspace state survives relaunch, disconnect, corruption and migration; restore report is truthful |
| G2: Browser endpoint | Browser receiver opens, pairs, presents the workspace and recovers committed state |
| G3: Identity and pairing | QR pairing rejects replay and expiry; devices can be revoked; discovery leaks no secrets |
| G4: Capabilities | Unauthorized, expired and revoked grants are denied; capability invocation is auditable |
| G5: Transport | WebSocket baseline meets the latency budget; any second transport is selected only after benchmark |
| G6: Accessibility | VoiceOver, keyboard-only, Dynamic Type, reduced motion and IME pass the supported matrix |

### Measurement definitions

- **Input acknowledgement latency:** controller dispatch to bridge acknowledgement.
- **Input-to-frame latency:** controller dispatch to display-side frame application time.
- **Warm restore:** process start to a usable restored workspace.
- **Committed-state loss:** loss of state that was already acknowledged as saved. In-flight writes may be lost under forced termination and must be reported.
- **Stuck input:** a pressed key or button that remains pressed after disconnect, focus loss or cancellation.

Targets are qualification hypotheses, not current measurements. Do not claim p95 results without a recorded scenario, device matrix and measurement method.

## 5. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Browser receiver cannot run Wanix without isolation headers | Feasibility spike before MVP commitment; fall back to external display |
| QR pairing scope expands into a full identity system | Local device identity and grants only; no account login in v1 |
| Workspace scope grows into sync and CRDTs | ADR-009 limits v1 to local persistence and truthful recovery |
| Protocol redesign destabilizes existing input | Extend ADR-008/FlatBuffers incrementally; conformance tests before migration |
| Cast or hardware qualification blocks release | Cast remains development-only until hardware is available |
| Transport work delays the browser endpoint | WebSocket first; WebRTC only after the endpoint is usable |
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
4. PROTO-01: approve ADR-010 through ADR-013.
5. Start WS-01 and PUTER-01.

Do not start the browser receiver implementation before END-01 resolves the isolation, secure-context and hosting questions.

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

## 9. Open business decision

The repository license is not decided by this plan. No SDK, reference receiver or host-agent publication should occur until the license, contribution model and trademark policy are chosen.

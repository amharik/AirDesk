# ADR-015: Session ownership and multi-controller input arbitration

- **Status:** Proposed — multi-controller and arbitration gates required
- **Date:** 2026-11-03
- **Deciders:** Product owner, engineering lead
- **Scope:** Session ownership, controller attachment, cursor identity, keyboard focus, input arbitration
- **Supersedes:** None
- **Related:** ADR-001, ADR-008, ADR-009, ADR-010, ADR-011, ADR-014

## Context

Session ownership is currently described in ADR-001 (Cast v2 handshake), ADR-010 (AD-LINK idempotency and cancellation), ADR-011 (session credentials) and now ADR-014 (browser aggregate sessions). The terms are not aligned.

The chosen product model is a parallel multi-device workspace:

- each device owns its local state;
- the browser aggregates connected device sessions for display;
- multiple devices can attach to one display;
- each device gets its own cursor color tagged with device name or ID;
- the user can choose between multi-input and single-input modes.

This needs one explicit session and arbitration model.

## Decision

### 1. One session vocabulary

| Term | Meaning | Owner |
| --- | --- | --- |
| Device identity | Stable key-bound identity | ADR-011 |
| Session | Time-bounded authenticated attachment | This ADR and AD-LINK |
| Workspace | Device-local state and resources | ADR-009 |
| Display session | Browser aggregate presentation surface | ADR-014 |
| Controller | Device contributing input | This ADR |
| Grant | Scoped capability authorization | ADR-012 |

- ADR-001's Cast v2 handshake is a transport-specific legacy handshake.
- AD-LINK is the canonical session-establishment vocabulary for ADFP.
- ADR-011 owns identity, pairing and credentials.
- ADR-009 owns persistence.
- ADR-012 owns capability authorization.

AD-LINK must state whether it subsumes or wraps the Cast v2 handshake. It may not define a second incompatible session concept.

### 2. Device-local ownership remains authoritative

- Each device owns its local workspace, files and runtime state.
- The browser display session is an aggregate view, not a replica.
- A controller attaching to a display does not transfer ownership of its local workspace.
- The display session may persist layout and controller presentation locally.
- Cross-device synchronization is future work.

### 3. Multi-controller is the default

- Each controller gets a stable session-scoped cursor identifier.
- Each cursor has a user-visible device label and a distinct color.
- Cursor color is assigned deterministically per session and device ID.
- A controller may move its pointer without stealing another controller's pointer.
- Pointer clicks apply at that controller's cursor position.
- A controller may disconnect without cancelling another controller's cursor.

### 4. Keyboard and text focus are single-owner

To avoid conflicting text entry:

- Exactly one controller owns keyboard and text focus at a time.
- Pointer ownership remains multi-device.
- Focus handoff is explicit: tap the workspace focus target on the desired controller, or use a controller-mode action.
- The focused controller is visibly indicated.
- When focus changes, the previous owner releases modifiers and committed text state.
- A disconnected keyboard owner releases all pressed keys.

### 5. Input modes are user-selectable

| Mode | Behavior |
| --- | --- |
| Multi-input | Multiple cursors; one keyboard owner; default |
| Single-input | One controller controls pointer and keyboard; others may request control |

Mode changes are session-scoped and visible. The mode must not silently change because a device disconnected.

### 6. Input arbitration is ordered and source-tagged

- Every input event carries `session_id`, `generation`, `sender_device_id` and sequence.
- Stale generations and duplicate sequences are rejected.
- Pointer movement may be coalesced per controller.
- Clicks, key releases, text commits and focus changes are never silently dropped.
- Input from a revoked or expired controller is rejected.
- Stuck-key cleanup runs on disconnect, focus loss and generation change.

### 7. Coordinator does not arbitrate content

The coordinator may coordinate membership, presence and handoff requests. It does not own cursor positions, focus state or workspace content in the MVP.

## Consequences

### Positive

- Removes duplicate session ownership language.
- Makes multi-device display behavior testable.
- Avoids conflicting keyboard input while allowing parallel pointers.
- Gives device labels and cursor colors a stable model.
- Keeps the coordinator out of content arbitration.

### Negative

- Multi-pointer UI, labels and colors add design and testing work.
- Keyboard focus handoff needs clear affordances.
- Input arbitration adds state to the shell and protocol.
- Single-input mode still needs a fair control-request flow.

## Acceptance gates

- Two controllers attach to one browser display with distinct cursors and labels.
- Simultaneous pointer movement does not move or steal the other cursor.
- Only one controller owns keyboard/text focus; handoff releases modifiers.
- Disconnect and generation changes release pressed keys and buttons.
- Single-input mode can be entered and exited without stale cursors.
- Revoked controllers cannot inject input.
- AD-LINK, ADR-001 and ADR-011 use one session vocabulary and state the Cast v2 relationship.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Single controller only | Rejected; product direction is a parallel multi-device workspace |
| Multiple cursors and multiple keyboard owners | Conflicting text entry and focus semantics |
| Per-device independent keyboards | Higher complexity; no clear MVP consumer |
| Coordinator-owned focus | Adds content-plane authority to the coordinator |

## Out of scope

- Collaborative document editing.
- Multiple simultaneous keyboard owners.
- Shared clipboard policy.
- Cross-device workspace synchronization.
- Coordinator-owned session metadata.

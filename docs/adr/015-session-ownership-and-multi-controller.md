# ADR-015: Workspace ownership, session ownership and multi-controller

- **Status:** Proposed — ownership and arbitration gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — workspace, session and controller ownership separated
- **Updated:** 2026-11-03 — peer review: epoch-fenced input leases and controller role taxonomy
- **Updated:** 2026-11-03 — peer review round 3: display-sink epoch ownership, pinned-role limits, guarded `force_preempt`, `EpochRejected`
- **Amended by:** ADR-020 (workspace host role and authority handoff)
- **Deciders:** Product owner, engineering lead
- **Scope:** Workspace ownership, display-session ownership, controller attachment, cursor identity, keyboard focus, input arbitration
- **Supersedes:** None
- **Amends:** ADR-001, ADR-008, ADR-014
- **Related:** ADR-009, ADR-010, ADR-011, ADR-012, ADR-016, ADR-017, ADR-018, ADR-020
- **Counters:** `docs/architecture/identifiers-and-counters.md`

## Context

Ownership language is fragmented across ADRs for Cast sessions, AD-LINK, credentials, browser endpoints and workspace persistence. The revised blueprint requires three distinct concepts:

- **workspace ownership** — the persistent logical environment;
- **session ownership** — the authority over one active display session;
- **controller attachment** — an endpoint currently providing input.

These must not be conflated. A controller is not a collaborator. A display session is not a workspace.

## Decision

### 1. Three ownership layers

| Layer | Meaning | Authority |
| --- | --- | --- |
| Workspace ownership | Persistent logical environment and desired state | ADR-016 workspace model |
| Session ownership | One active presentation session and its lifecycle | `SessionCoordinator` under ADR-017 |
| Controller attachment | An endpoint contributing input to a session | This ADR |

- Device trust is not workspace ownership.
- A controller attachment is not workspace membership.
- A display session cannot write canonical workspace state.
- Multiple controllers do not imply multiple workspace owners.
- Multi-user collaboration requires a separate membership and role model.

### 2. Session vocabulary

| Term | Meaning | Owner |
| --- | --- | --- |
| Device identity | Stable key-bound identity | ADR-011 |
| Workspace | Persistent desired state and resources | ADR-016 |
| Display session | Time-bounded presentation of a workspace | ADR-014 and this ADR |
| Controller | Endpoint currently providing input | This ADR |
| Capability lease | Bounded authorization to use a capability | ADR-012/018 |

- AD-LINK is the canonical ADFP session-establishment vocabulary.
- ADR-011 supplies identity, pairing and credentials.
- ADR-001's Cast v2 handshake is a transport-specific legacy handshake.
- AD-LINK must state whether it wraps or subsumes Cast v2; it may not define a second incompatible session model.

### 3. Workspace ownership survives session changes

- Closing a display session does not close or delete the workspace.
- A controller disconnect does not change workspace ownership.
- A revoked device loses trust; it does not delete the workspace.
- Replacing a browser endpoint creates a new display session for the same workspace.
- Workspace recovery is owned by the orchestrator and workspace store, not the session coordinator.

### 4. Multi-controller is the default for a personal workspace

- Each controller gets a stable session-scoped cursor identifier.
- Each cursor has a user-visible device label and a distinct color.
- Cursor color is assigned deterministically per session and device ID.
- A controller may move its pointer without stealing another controller's pointer.
- Pointer clicks apply at that controller's cursor position.
- A controller may disconnect without cancelling another controller's cursor.
- A device joining as a controller is not automatically a collaborator.

### 4.1 Controller roles and epoch-fenced leases

Every controller holds one runtime role per seat. The `SessionCoordinator` co-located with the display sink maintains a monotonically increasing `lease_epoch: uint64` and an `active_controller_id` for that display session. `lease_epoch` is session state, is never persisted in the workspace manifest, and resets with each new `generation` (ADR-020 §2).

| Role | Count | Authority |
| --- | --- | --- |
| `PRIMARY_DRIVER` | 1 per seat | Exclusive write lease for the shared cursor and active-window keyboard/text focus |
| `PINNED_SURFACE_DRIVER` | 0..K per workspace | Pointer, touch and scroll input scoped to one window (`target_window_id`) or PTY (`target_pty_id`). No keyboard, text or focus authority |
| `PASSIVE_OBSERVER` | 0..M per workspace | Receives state/preview frames; cannot emit input until it requests a lease |

The **shared cursor** is the single workspace-visible pointer position for a display session. Only the `PRIMARY_DRIVER` writes it. In multi-input mode other controllers may render local cursors for their own feedback, but those cursors do not move the shared cursor and do not imply input authority over the active window.

Lease state machine:

| Current | Trigger | Guard | Action and broadcast | Next |
| --- | --- | --- | --- | --- |
| `LEASE_ACTIVE(C_A, E)` | `C_B` sends `RequestLease(PRIMARY)` | `C_A` idle >500 ms, or `C_B.force_preempt` accepted under the guard below | `epoch = E+1`; inject `ReleaseAllButtonsAndModifiers()`; broadcast `LeaseChanged(C_B, E+1)` | `LEASE_ACTIVE(C_B, E+1)` |
| `LEASE_ACTIVE(C_A, E)` | `C_B` sends a reliable input edge with `epoch < E` | `frame.epoch != E` | Reject with `EpochRejected(current_epoch = E)`; increment `stale_epoch_drops`; a packed movement frame with a stale epoch is dropped silently | `LEASE_ACTIVE(C_A, E)` |
| `LEASE_ACTIVE(C_A, E)` | `C_A` disconnects or misses 3 × 1 s heartbeats | `now - C_A.last_seen > 3000 ms` | `epoch = E+1`; inject `ReleaseAllButtonsAndModifiers()`; promote the highest-priority standby or enter `LEASE_UNCLAIMED(E+1)` | `LEASE_UNCLAIMED(E+1)` |

Rules:

- Every packed movement frame carries `lease_epoch_lo` and every reliable input edge carries `lease_epoch`; frames whose epoch does not match the current session epoch are discarded before dispatch. A stale reliable edge is answered with `EpochRejected(current_epoch)` so the controller can resynchronize; a stale movement frame is dropped without a reply.
- A leadership transition increments the epoch and synthesizes a full button/modifier release before the new lease is granted.
- `PINNED_SURFACE_DRIVER` may send pointer, touch and scroll input only for its scoped target. It does not move the shared cursor and cannot emit keyboard, text, focus or any event that changes active-window focus. Focus and text remain exclusively with `PRIMARY_DRIVER`.
- Cursor ownership remains multi-device in multi-input mode; the primary lease governs keyboard/text focus and shared-cursor authority.
- A controller cannot grant itself a lease or reuse an epoch.
- `force_preempt` is privileged and guarded: the controller must present explicit user confirmation on the requesting device, the coordinator rate-limits it to one accepted preemption per controller per 10 seconds, and every accepted or rejected attempt is recorded in the audit log with both controller identities and the old/new epoch. A `force_preempt` without confirmation is rejected as `PreemptionNotConfirmed`.
- `lease_epoch` belongs to the display session's `SessionCoordinator`, not to the workspace host. A new `generation` starts at a fresh lease state; a reconnecting controller must re-request a lease rather than assume its previous epoch.

### 5. Keyboard and text focus are single-owner

- Exactly one controller owns keyboard and text focus at a time.
- Pointer ownership remains multi-device.
- Focus handoff is explicit: tap the workspace focus target on the desired controller, or use a controller-mode action.
- The focused controller is visibly indicated.
- When focus changes, the previous owner releases modifiers and committed text state.
- A disconnected keyboard owner releases all pressed keys.
- Input from a non-focus controller for keyboard, text or focus events is rejected.

### 6. Input modes are user-selectable

| Mode | Behavior |
| --- | --- |
| Multi-input | Multiple cursors; one keyboard owner; default |
| Single-input | One controller controls pointer and keyboard; others may request control |

Mode changes are session-scoped and visible. The mode must not silently change because a device disconnected.

### 7. Input arbitration is ordered and source-tagged

- Every reliable input event carries `session_id`, `generation`, `sender_device_id`, `controller_id`, `input_source`, sequence and `lease_epoch`. Packed movement frames carry `lease_epoch_lo` and `seq`; the receiver derives session, generation and controller from the authenticated connection (ADR-008).
- Stale generations, stale `lease_epoch` values and duplicate sequences are rejected.
- Pointer movement may be coalesced per controller.
- Clicks, key releases, text commits and focus changes are never silently dropped.
- Input from a revoked or expired controller is rejected.
- Stuck-key cleanup runs on disconnect, focus loss and generation change.
- The wire fields are owned by ADR-008; this ADR owns their arbitration semantics.

### 8. Coordinator and runtime do not arbitrate content

The coordinator may coordinate membership, presence and handoff requests. A runtime provider may route input to an application. Neither owns cursor positions, focus state or workspace content.

## Consequences

### Positive

- Workspace, session and controller ownership are unambiguous.
- Workspace state survives display and controller changes.
- Makes multi-device presentation behavior testable.
- Avoids conflicting keyboard input while allowing parallel pointers.
- Prevents multi-controller support from being mistaken for collaboration.

### Negative

- Multi-pointer UI, labels and colors add design and testing work.
- Keyboard focus handoff needs clear affordances.
- Input arbitration adds state to the shell and protocol.
- Single-input mode still needs a fair control-request flow.

## Acceptance gates

- Workspace identity and ownership survive display-session close and controller disconnect.
- Two controllers attach to one display session with distinct cursors and labels.
- Simultaneous pointer movement does not move or steal the other cursor.
- Only one controller owns keyboard/text focus; handoff releases modifiers.
- Disconnect and generation changes release pressed keys and buttons.
- A leadership change increments `lease_epoch` and synthesizes a full button/modifier release before the new lease is active.
- A reliable edge with a stale `lease_epoch` is answered with `EpochRejected(current_epoch)` and counted; a packed movement frame with a stale epoch is dropped silently. A `PINNED_SURFACE_DRIVER` cannot move the shared cursor or emit keyboard/text/focus input.
- `force_preempt` without device confirmation is rejected; accepted attempts are rate-limited and audited.
- A new `generation` resets `lease_epoch` and no earlier epoch is accepted.
- Single-input mode can be entered and exited without stale cursors.
- Revoked controllers cannot inject input.
- Pairing and controller attachment do not grant workspace ownership or collaboration rights.
- AD-LINK, ADR-001, ADR-011 and ADR-016 use one ownership vocabulary and state the Cast v2 relationship.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Single controller only | Rejected; product direction is a parallel multi-device workspace |
| Multiple cursors and multiple keyboard owners | Conflicting text entry and focus semantics |
| Per-device independent keyboards | Higher complexity; no clear MVP consumer |
| Controller attachment implies workspace ownership | Conflates session role with persistent workspace authority |

## Out of scope

- Collaborative document editing.
- Multiple simultaneous keyboard owners.
- Shared clipboard policy.
- Cross-device workspace synchronization.
- Multi-user workspace membership and roles.
- Coordinator-owned workspace metadata.

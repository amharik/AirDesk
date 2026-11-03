# ADR-020: Workspace host role, duty split and authority handoff

- **Status:** Proposed — host-role, handoff and degraded-mode gates required
- **Date:** 2026-11-03
- **Deciders:** Product owner, engineering lead, security owner
- **Scope:** Where workspace authority runs, which duties it carries, what happens when it is unreachable, how it moves between devices
- **Supersedes:** None
- **Amends:** ADR-009, ADR-012, ADR-015, ADR-016, ADR-017
- **Related:** ADR-004, ADR-010, ADR-011, ADR-013, ADR-014, ADR-018, ADR-019
- **Counter reference:** `docs/architecture/identifiers-and-counters.md`

## Context

ADR-016 makes the workspace independent of devices, runtimes and display sessions, and says Release 1 uses "a single local authority". Later amendments hand that authority more work without saying where it runs:

| Duty | Stated in | Phrase used |
| --- | --- | --- |
| Single-writer store commit | ADR-009 §6 | "one writer per workspace revision" |
| Structural sequencing (`workspace_seq`) | ADR-016 §7.1 | "workspace host … Single-Writer Sequencer" |
| Lease arbitration (`lease_epoch`) | ADR-015 §4.1, `device-fabric.md` | "the workspace authority maintains … `lease_epoch`" |
| Grant issuance | ADR-012 §4, `device-fabric.md` | "local workspace authorization service" / "workspace authority issues … tokens" |
| Orchestration and reconciliation | ADR-017 | `WorkspaceOrchestrator` |

Three questions are unanswered in the headline scenario (iPhone as controller, desktop browser as display):

1. **Which device is the host?** The browser is excluded (ADR-014 §2). ADR-011 §7 and ADR-014 say an iOS app cannot be an always-on listener. `deployment-topologies.md` Topology 2 says "workspace/orchestrator (host device)" without naming it.
2. **What happens when the host is unreachable?** ADR-016 gates say a device disconnect leaves desired state intact, but not what the display may still do.
3. **How does authority move?** ADR-016 §2 says a workspace "may be opened on a different endpoint", while ADR-009 §11 puts cross-device resume out of scope. Moving authority needs a rule that does not depend on synchronization.

Two of the duties above also have different latency and availability needs. Input lease arbitration sits on the 50 ms pointer path (ADR-005). Structural sequencing does not. Putting both on one possibly suspended device is the wrong coupling.

## Decision

### 1. Define the `WorkspaceHost` role narrowly

`WorkspaceHost` is a logical role held by exactly one device per workspace at a time. It carries three duties:

- **Store writer:** the only process that commits manifest revisions (ADR-009 §6).
- **Structural sequencer:** assigns `workspace_seq` (ADR-016 §7.1).
- **Orchestrator:** runs `WorkspaceOrchestrator` reconciliation (ADR-017).

It does **not** carry lease arbitration or grant issuance (sections 2 and 3).

The role is identified by `host_epoch: uint64`, stored in the manifest `recovery` block. Peers reject structural messages whose `host_epoch` is lower than the highest value they have seen.

### 2. Lease arbitration belongs to the display session, not the host

`lease_epoch` (ADR-015) is session-scoped state owned by the `SessionCoordinator` co-located with the display sink (the local host agent in the browser topology, the native external-display scene otherwise).

- Arbitration needs no round trip to the workspace host, so a suspended phone cannot stall input.
- `lease_epoch` is never persisted in the manifest and resets with a new display-session `generation`. Frames are bound to the generation by the authenticated connection (see `identifiers-and-counters.md`).
- The workspace host learns of lease changes only as presentation metadata. It does not arbitrate them.

This replaces the "workspace authority arbitrates input" wording in `device-fabric.md` and ADR-015 §4.1.

### 3. Grant issuance belongs to the approving device

Per ADR-012 §4, root grants for a capability are issued by the **provider device's** user approval or by the workspace owner key, never by the requester and never by the coordinator. The workspace host may sign delegated hops (ADR-012 §4.2 depth ≤ 3) but holds no root authority over another device's capabilities. A host change does not change who can approve a capability.

### 4. Default placement

| Scenario | Default `WorkspaceHost` |
| --- | --- |
| Single native device (Release 1) | That device |
| Phone controller plus browser display (Release 2/3) | The device holding the canonical native store, normally the phone or tablet |
| User has moved the workspace | The device named by the last completed handoff |

The browser and its local host agent are display and optional runtime hosts. They become `WorkspaceHost` only through an explicit handoff (section 6) to a native agent. A browser profile is never a valid target, because its storage is evictable (ADR-009 §11).

### 5. Host-degraded mode is a normal state

When the host is unreachable (iOS suspension, network loss, app exit) a display session enters `host-degraded`:

- Already-running runtimes on the display-side agent keep running and presenting. Their observed state stays local.
- Input continues under existing leases and unexpired capability tokens.
- Structural mutations (open or close window, change application definition, change placement) are **rejected with a typed error**. They are not queued, because queued writes would become a second writer.
- Layout geometry changes are held as session-local presentation state and are offered to the host on reconnect as ordinary mutations, subject to `workspace_seq` checks.
- No new grants are issued by the host. Existing tokens expire normally.
- The UI states that the workspace host is unavailable and shows which device it is.

On reconnect the host runs reconciliation (ADR-017 §6). Nothing in degraded mode rewrites desired state.

### 6. Handoff is explicit, user-initiated and fenced

Automatic leader election is out of scope. A handoff from host A to native agent B proceeds as:

1. **Quiesce:** A stops accepting structural mutations.
2. **Final checkpoint:** A commits revision *R* with `workspace_seq = N` and records `host_epoch = H`.
3. **Transfer:** A sends manifest, journal snapshot and integrity hash to B over a device-authenticated channel (ADR-011), under a lease for `workspace.host.transfer` approved by the user.
4. **Stage:** B verifies schema, integrity and `workspace_seq = N`, and holds the import in `staged`. B is not yet host.
5. **Activate:** A sends `activate(H+1)`. B commits with expected revision *R*, sets `host_epoch = H+1`, and becomes host.
6. **Retire:** A marks its copy `handed-off` (read-only backup, not authority).

If steps 3–5 fail or time out, A resumes as host at `H`. No epoch change occurs and B discards the staged import.

**Force takeover** (A is lost): the user may promote B from its last staged or backup copy. B sets `host_epoch = H+1`, reports the last known `workspace_seq` and states that later mutations are lost. If A returns, it observes a higher `host_epoch`, demotes itself to read-only and shows the divergence. No automatic merge occurs.

### 7. Resource locality does not move with authority

`ResourceReference` entries keep their `providerId`. A handoff moves the manifest, not the data. A `runtime-volume` backed by browser OPFS carries `persistence: evictable` and is excluded from zero-loss claims (ADR-009 §5). After a handoff, references whose provider is unreachable become `unavailable` (ADR-016 §5), not rewritten.

### 8. iOS availability is stated, not hidden

A phone holding the host role is expected to be suspended. `host-degraded` is the designed response, not a failure. Release documentation must not promise that a phone-hosted workspace stays mutable while the app is suspended. A user who needs an always-available host moves the workspace to a native desktop agent (ADR-018).

## Consequences

### Positive

- One answer to "where is the authority" for each duty.
- Input arbitration no longer depends on a device iOS may suspend.
- Single-writer semantics hold across devices without synchronization.
- Failure behavior (degraded mode, force takeover) is specified and testable.

### Negative

- Adds `host_epoch` and a handoff protocol to the manifest and AD-WS.
- The phone-controller scenario shows a read-only display whenever the phone is suspended.
- Force takeover can lose mutations, and the UI must say so.
- Two arbiters (host for structure, session coordinator for input) must be kept distinct in code and docs.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Single "workspace authority" for all duties | Couples 50 ms input arbitration to a device that may be suspended |
| Coordinator as host | Violates ADR-014 §4 and ADR-016 §7 |
| Browser or display machine always hosts | Violates workspace independence; browser storage is evictable |
| Automatic leader election (Raft or similar) | A distributed-consensus scheduler is a stated non-goal; two to three personal devices do not justify it |
| Queue structural writes while degraded | Creates a second writer; conflicts with ADR-009 §6 |

## Acceptance gates

- Exactly one device accepts structural mutations for a workspace at any time; a stale `host_epoch` is rejected by peers.
- A suspended or disconnected host puts display sessions into `host-degraded`: structural writes fail with a typed error, running runtimes and leased input continue.
- A completed handoff changes `host_epoch` once, preserves `workspace_seq` continuity and leaves the old host read-only.
- An interrupted handoff leaves the original host authoritative with no epoch change.
- Force takeover reports the last known `workspace_seq`, and a returning old host demotes itself.
- Lease arbitration works with the workspace host offline.
- A browser profile cannot be the target of a handoff.
- Root capability grants are never issued by the requester, the coordinator or a display endpoint.

## Out of scope

- Automatic host election or failover.
- Multiple simultaneous hosts for one workspace.
- Synchronization and merge across hosts (ADR-009, Release 4).
- Collaborative membership (Release 5).

# Identifiers, epochs and sequence counters

Location: `docs/architecture/identifiers-and-counters.md`. Referenced from ADR-008, ADR-009, ADR-012, ADR-015, ADR-016 and ADR-020.

The ADRs define several monotonic values that all read as "the sequence". They have different owners, scopes and lifetimes, and several reviews found text that mixes them. This table is the single reference. A new counter must be added here before an ADR introduces it.

## Registry

| Name | Type | Scope | Owner (assigns) | Persisted | Advances when | Checked by | Defined in |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `manifest.revision` | uint64 | One workspace | `WorkspaceStore` (host) | Yes, manifest | Each committed manifest revision | Store, on commit (`expected revision`) | ADR-009 §1, §6 |
| journal sequence | uint64 | One workspace | `WorkspaceStore` (host) | Yes, journal | Each journal entry appended | Recovery replay | ADR-009 §4 |
| `checkpoint_seq` | uint64 | One workspace, native store flush | `WorkspaceStore` | Yes | Each acknowledged native durable flush | Recovery, to bound journal replay | ADR-009 §5.1 |
| `webcontent_checkpoint_seq` | uint64 | One WebContent/OPFS store | WebContent store | Yes, WebContent | Each acknowledged WebContent flush | Recovery report; never stalls native commit | ADR-009 §5.1 |
| `workspace_seq` | uint64, contiguous | One workspace | `WorkspaceHost` sequencer | Yes | Each accepted structural mutation | Host, on mutation (`expected workspace_seq`) | ADR-016 §7.1 |
| `host_epoch` | uint64 | One workspace | Handoff protocol | Yes, manifest `recovery` | Each completed handoff or force takeover | Peers, on structural messages | ADR-020 |
| session `generation` | uint64 | One display session | `SessionCoordinator` | No | Each new session or reconnect that invalidates old frames | Receiver, on every input frame | ADR-001, ADR-008 |
| `lease_epoch` | uint64 | One display session | `SessionCoordinator` at the display sink | No | Each input-lease transition | Input ingress | ADR-015 §4.1 |
| `lease_epoch_lo` | uint16 | Frame field | Derived from `lease_epoch` | No | Mirrors low 16 bits of `lease_epoch` | Input ingress (fast path) | ADR-008 packed frame |
| input `seq` | uint32 in packed frame, uint64 in envelope | One controller on one connection | Controller | No | Each frame sent | Receiver (`seq` ≤ last is dropped) | ADR-008 |
| revocation sequence | uint64 | One issuer | Issuer | Yes | Each revocation record | Provider, for staleness | ADR-012 §4 |
| stream `seq` | uint64 | One AD-RUNTIME stream | Producer | No | Each message or byte range | Consumer | `ad-runtime.md` |
| token `epoch_id` | see rule 5 | One grant | Grant issuer | In token | Never (fixed at issue) | Provider, on every host call | ADR-012 §4.2 |

## Rules

1. **Counters never substitute for each other.** `checkpoint_seq` orders durable native flushes only. It is not a manifest revision and not a `workspace_seq` (ADR-009 §5.1 already says this; keep the sentence in every ADR that mentions it).
2. **Each counter has exactly one assigner.** Display sessions, runtimes, browser endpoints and the coordinator never assign `workspace_seq`, `manifest.revision` or `host_epoch`. The workspace host never assigns `lease_epoch` or `generation`.
3. **Binding to the connection replaces missing frame fields.** The 16-byte `PackedPointerFrame` has no `sessionId`, `generation` or `controllerId`. The receiver must derive them from the authenticated transport connection the frame arrived on. A frame received on a connection from a previous session must be discarded by the transport, not by the frame (ADR-008 states this). It holds for QUIC datagrams and WebTransport because datagrams are scoped to one encrypted connection. It does **not** hold for any shared or unauthenticated path.
4. **Wraparound.** A `uint32` input `seq` at 120 Hz wraps in about 414 days. Compare with serial-number arithmetic (RFC 1982) over a half-range window, and reset `seq` and last-seen on every new connection or `lease_epoch` change. `lease_epoch_lo` wraps after 65,536 transitions; the receiver compares it only against the low 16 bits of the current epoch and relies on rule 3 for stale-session protection.
5. **`epoch_id` in capability tokens means session `generation`, not `lease_epoch`.** `lease_epoch` can change every few hundred milliseconds during controller handoff (ADR-015 §4.1). Binding tokens to it would invalidate every grant on each handoff. If a token must be bound to a controller role, use a separate `role` claim.
6. **Persisted versus volatile is part of the contract.** Only `manifest.revision`, journal sequence, `checkpoint_seq`, `webcontent_checkpoint_seq`, `workspace_seq`, `host_epoch` and the revocation sequence survive restart. After a restart, volatile counters start from a new `generation`, never from a remembered value.
7. **Geometry ordering uses host receive order.** With a single-writer host the total order is the order the host accepts updates; add a deterministic tie-break on `controllerId` only if two updates arrive in one scheduling tick. Last-writer-wins by timestamp or client counter belongs to the Release 4 synchronization layer, not to v1.
8. **`lease_epoch_lo` is deliberate.** The fast path carries only the low 16 bits. Stale-session and full-epoch correctness come from the authenticated connection binding (rule 3) plus the input ingress check; a frame is never trusted on `lease_epoch_lo` alone.

## Open items

- Add a column or note for wire width once the FlatBuffers `Envelope` field IDs are frozen (ADR-008 evolution rules).
- Decide whether `webcontent_checkpoint_seq` is stored durably enough to survive OPFS eviction, or is reported as `unknown` with the resource marked `degraded`.

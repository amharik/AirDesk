# ADR-028: Operation-based workspace sync

- **Status:** Accepted — core operation log only; platform cutover pending P3-08
- **Date:** 2026-11-13
- **Deciders:** Workspace and shared-core engineering
- **Related:** ADR-009, ADR-016, ADR-020, ADR-024, P3-03, P4-11

## Context

The current workspace sync path carries field patches with `revision` and
`deviceId`, then applies `lww`, `append-log` or `manual` merge classes at the
receiver. That model is covered by a deterministic conflict corpus, but the
authoritative order is still the host's receive order. Offline peers and
multiple writers therefore depend on rebasing and retry logic rather than a
single convergent history.

P4-11 requires an operation log with Lamport/actor ordering, deterministic
offline and multi-writer convergence, and preservation or migration of the
existing merge fixtures. P3-03 and P1-02 are complete, and ADR-024 makes the
additive Rust core the place for platform-neutral deterministic logic.

## Decision

1. **Operations are the synchronization unit.** An operation has a globally
   unique `id`, an `actor`, a positive `lamport` timestamp and one of two
   intents:
   - `set-field { path, value }`;
   - `append-entry { path, key, value }`.
2. **The total order is `(lamport, actor, id)`.** Lamport values order causally
   related edits; the actor id breaks equal-timestamp ties; the operation id
   breaks any remaining duplicate-actor tie. Projection always sorts by this
   order, independent of network or log-arrival order.
3. **Each actor owns a persistent Lamport clock.** A local operation ticks the
   clock. Observing a remote operation advances the clock to at least that
   timestamp. The clock is not global and does not require a coordinating host.
4. **Logs merge by operation identity.** Merging two logs is a union keyed by
   `id`. Exact replays are idempotent. Reusing an `id` for different content is
   rejected instead of silently choosing a history.
5. **Field metadata still chooses the projection rule.** `lww` takes the last
   operation in total order; `append-log` unions entries by key, sorts keys
   lexicographically and resolves duplicate keys by maximum canonical JSON
   value with total order as the tie-breaker, matching the existing field
   merge; unregistered or `manual` fields take the last operation but report a
   conflict when concurrent values differ.
6. **Conflicts are explicit and convergent.** Both peers choose the same
   deterministic winner — the highest-order operation, or the highest-order
   operation carrying the maximum canonical append value — and report the same
   losing operation ids. A manual conflict is never silently resolved as if it
   had been merged.
7. **The existing field-merge corpus is preserved.** No `lww`, `append-log` or
   `manual` fixture is rewritten or deleted. The new operation-log fixture is
   additive and proves convergence in forward, reverse and flattened merge
   order.
8. **No CRDT or vector-clock adoption follows from this ADR.** The operation
   log is sufficient for the current field model. A different convergence
   model, rich-text collaboration or tombstone scheme requires a new ADR and a
   migration corpus.

## Consequences

### Positive

- Offline peers can merge logs without a host receive order.
- Replaying a log, or receiving the same operation twice, is harmless.
- Multi-writer conflicts are reproducible and visible.
- The convergence rules live in one shared crate instead of platform-specific
  merge code.

### Negative

- Logs grow with editing history and need compaction or checkpointing before
  production use.
- Every actor must persist its Lamport clock; losing it can produce ties or
  ordering anomalies.
- `manual` fields still require UI resolution even though the projected winner
  is deterministic.
- The current `revision`/`deviceId` patch format is not yet replaced, so a
  temporary translation layer will exist during cutover.

## Acceptance gates

- The operation-log fixture converges to identical fields and conflicts for
  every tested log-merge order.
- Exact operation replay is idempotent and conflicting duplicate ids fail
  closed.
- Operation kinds must match their registered merge class.
- Existing workspace sync fixtures and platform tests remain green.
- Core `fmt`, `clippy -D warnings` and locked tests pass.
- Platform cutover additionally requires P3-08 flags, UniFFI/WASM exports,
  cross-language fixture parity and a rollback path. None of those is claimed
  by this core-only decision.

## Out of scope

- Replacing the current Swift, TypeScript or Kotlin sync runtime.
- Encrypted transport, key distribution or envelope changes.
- Tombstones, log compaction and checkpoint persistence.
- Multi-user membership or CRDT-based rich-document collaboration.

# ADR-026: Persistent PTY daemon boundary

- **Status:** Proposed — implementation in progress
- **Date:** 2026-11-11
- **Deciders:** Engineering lead, security owner, platform owners
- **Scope:** `airdeskd`, persistent PTY ownership, ADFP terminal attachment, leases, replay and client lifecycle
- **Supersedes:** None
- **Amends:** ADR-007, ADR-010, ADR-024
- **Related:** ADR-008, ADR-012, ADR-013, ADR-018, ADR-021

## Context

ADR-024 keeps SSH, local PTY and process spawning outside the shared portable Rust core. That boundary is still correct: `airdeskd` owns an ambient OS process, a filesystem path, a listening socket and a child PTY, while the shared core receives typed data and returns typed results.

The product still needs a persistent terminal whose process survives controller disconnects. A controller may detach, reconnect, or attach from a second device and must receive a bounded replay without restarting the shell. Putting this state machine in `airdesk-core` would violate ADR-024. Leaving it entirely on each client would duplicate replay, lease and multi-client policy.

## Decision

### 1. `core/airdeskd` is a standalone daemon, not a shared-core crate

`core/airdeskd` is an isolated Cargo package with its own `[workspace]` and lockfile. It is not a member of the shared `core` workspace and must not be linked into iOS, Android, web or UniFFI/WASM targets.

The daemon may depend on the protocol crate for generated ADFP types. It must not depend on `airdesk-core` or `airdesk-ffi`.

### 2. The daemon owns only terminal I/O and attachment state

The daemon owns:

- the PTY master/slave pair and child process;
- reads, writes and window resizes;
- a bounded replay buffer;
- attached client membership and per-client outbound queues;
- local lease-file loading and lease authorization.

The daemon does not own workspace authority, device identity, pairing, capability issuance, display sessions, audit policy or user consent. Those remain in the existing native/browser paths.

### 3. ADFP terminal messages are additive

`TerminalMessage` is an additive member of the separate `FabricPayload` union. The v1 `MessagePayload` union and existing `Envelope` members remain unchanged.

A terminal frame carries:

- type (`attach`, `attached`, `data`, `resize`, `detach`, `exit`, `error`);
- session and client identifiers;
- an optional `CapabilityLease` reference;
- data sequence, replay-from sequence and oldest retained sequence;
- raw PTY bytes for `data`;
- columns, rows, exit code, message and replay-truncation flag.

Raw terminal bytes are not interpreted as UTF-8 by the daemon. Sequence numbers order replay and let clients drop duplicates.

Transport framing is a 4-byte big-endian length prefix around the FlatBuffer envelope, capped at 1 MiB. A transport binding must validate the length before reading the payload.

### 4. Leases gate every terminal operation

The initial capability URI is `airdesk://pty/spawn`. Requests carry only a lease id; the daemon checks it against locally provisioned leases.

- `attach` requires an unexpired, non-revoked lease with the spawn capability;
- `write`, `resize` and `detach` require an attached client and a currently valid lease;
- attaching checks the lease before allocating replay or client state;
- expiry or revocation ends the attachment on the next operation;
- the daemon never logs terminal bytes or lease secrets.

This is local enforcement only. Issuance, distribution and revocation transport remain under ADR-012 and are not implemented by this decision.

### 5. Replay is bounded and sequence-based

The default replay budget is 256 KiB or 4096 chunks, whichever is reached first; each PTY read is at most 8 KiB. When the buffer is full, the oldest chunks are discarded.

`attach` supplies `replay_from_sequence`; `attached` returns the oldest retained sequence and whether replay was truncated. Clients must treat a gap as truncation, not as ordered data, and must not claim zero lost bytes when the truncation flag is set.

The daemon must not grow the replay buffer based on client requests.

### 6. Client lifecycle is explicit and bounded

- Up to 8 clients may attach to one session by default.
- Each client has a bounded outbound queue; a slow client is removed rather than blocking PTY readers.
- Detach removes only that client.
- The child PTY is closed and SIGHUP is sent when the session is closed.
- Reconnect creates a new client id and resumes from the last accepted sequence.

### 7. Unix socket is the first binding

The initial daemon listens on a local Unix domain socket. It is not a network-exposed service and makes no SSH, Iroh, WebSocket or local-forward transport claim.

Authentication of the socket peer is delegated to the host OS socket permissions. Lease checks are defense in depth, not a replacement for transport authentication.

### 8. Rollback and qualification

The daemon is additive. Clients may keep the existing direct SSH PTY path until terminal attach/replay integration is tested.

No physical-device, live-network, process-survival-under-network-migration, zero-lost-byte or latency qualification is claimed from loopback/Unix-socket tests. P5-05 owns OSC 133 replay and handoff behavior.

## Consequences

- Persistent PTY behavior no longer forces platform I/O into the shared core.
- Terminal attachment has its own process and failure domain.
- The daemon needs its own build, test, packaging and supervision story.
- Lease issuance and transport authentication remain separate, incomplete work.
- ADFP gains a terminal payload without changing the v1 baseline union.

## Verification

- `cargo test --offline` in `core/airdeskd` covers frame round-trips, bounded replay/truncation, multi-client attach, reconnect sequence, lease denial/revocation/expiry, operation authorization, Unix-socket framing and a real `/bin/sh` PTY byte tee.
- `protocol/check.sh` must pass after generated bindings change.
- Swift client coverage validates ADFP encode/decode, split length-prefixed frames and duplicate/sequence replay handling.
- These tests are code-level evidence only. They do not satisfy live-network or physical-device gates.

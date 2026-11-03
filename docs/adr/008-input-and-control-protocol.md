# ADR-008: Canonical input and control protocol

- **Status:** Proposed — schema generation and contract tests required
- **Date:** 2026-10-29
- **Updated:** 2026-11-03 — Input source, focus owner and controller arbitration added
- **Updated:** 2026-11-03 — peer review: dual-path wire discriminator, FlatBuffers evolution rules and conformance gate
- **Updated:** 2026-11-03 — peer review round 3: movement-only packed frame, reliable edge channel, connection-derived context and latency probe
- **Amended:** 2026-11-03 — channel-first routing and layout portability added; packed frames no longer carry edges or timestamps.
- **Scope:** Input event vocabulary, schema ownership, coordinates, coalescing, click semantics, session/generation/sequence rules, multi-controller arbitration
- **Supersedes:** None
- **Related:** ADR-001, ADR-002, ADR-005, ADR-007, ADR-010, ADR-015, ADR-017
- **Counters:** `docs/architecture/identifiers-and-counters.md`

## Compatibility decision (M0-04)

Negotiate both the legacy v1 JSON envelope and PackedPointerFrame v12. A session uses v12 only when both peers advertise v12, both advertise packed movement version 12, and both support the reliable edge channel; every other session falls back to legacy v1. There is no hard cutover in Release 1. Legacy v1 remains read-only compatibility surface and must not grow new event types. The decision is implemented by `InputProtocolNegotiator`, `InputChannelRouter` and `PackedMovementFrame`.

## Decision

Adopt one canonical input vocabulary shared by native gestures, the Air Cursor controller, hardware keyboards, the web shell, Cast, and future remote sessions.

- Transport carries **11 input event types** plus a separate control-message set.
- Session start/end are control messages, not input events.
- A neutral IDL plus a packed-frame specification is the source of truth. Swift, TypeScript, and Rust bindings are generated from it.
- Pointer coordinates are normalized to `0...1`; viewport dimensions are logical pixels.
- Pointer movement is coalesced at 120 Hz with an 8 ms latest-wins window.
- Taps use `pointerDown` + `pointerUp`; the shell synthesizes one DOM click. `pointerClick` remains reserved for constrained sources and must not be paired with down/up for the same gesture.

## Canonical input events

| Event | Payload | Semantics |
|---|---|---|
| `pointerMove` | `x`, `y` | Normalized cursor movement. Coalescible. |
| `pointerDown` | `x`, `y`, `button`, `clickCount` | Primary press. Ordered and non-coalescible. |
| `pointerUp` | `x`, `y`, `button`, `clickCount` | Primary release. Ordered and non-coalescible. |
| `pointerClick` | `x`, `y`, `button`, `clickCount` | Constrained-source semantic click; not sent with down/up for the same gesture. |
| `pointerCancel` | optional reason | Cancels the active gesture and releases captured state. |
| `scroll` | `dx`, `dy` | Ordered, bounded scroll delta. |
| `keyDown` | `key`, `code`, `modifiers` | Ordered key press; used for shortcuts and navigation. |
| `keyUp` | `key`, `code`, `modifiers` | Ordered key release. |
| `textInput` | `text` | Committed text from the platform keyboard or IME. |
| `focusChanged` | `target` | Bounded focus target identifier. |
| `viewportChanged` | `width`, `height` | Logical display pixels. |

Control messages include session lifecycle, readiness, acknowledgements, appearance, runtime state, and shell actions. ADR-001 owns the session handshake; this ADR owns the input vocabulary.

## Multi-controller input context

Every reliable input event carries an envelope in addition to its event payload. Packed movement frames omit these fields and derive them from the authenticated connection (see "Connection-derived context").

| Field | Purpose |
| --- | --- |
| `sessionId` | Display session receiving the input |
| `generation` | Session epoch; stale generations are rejected |
| `senderDeviceId` | Authenticated controller identity |
| `controllerId` | Session-scoped controller attachment |
| `sequence` | Monotonic per-controller sequence |
| `inputSource` | `pointer`, `keyboard`, `touch`, `stylus`, `hardware` or `ime` |
| `focusOwnerId` | Current keyboard/text focus owner, when applicable |

Rules:

- Pointer events identify their controller and render at that controller's cursor.
- Keyboard, text and focus events are accepted only from the current focus owner.
- A focus handoff includes a new `focusChanged` message with the new owner and releases modifiers on the previous owner.
- Disconnect, focus loss and generation change release pressed keys and buttons.
- Duplicate controller IDs, stale generations and revoked devices are rejected.
- Input source is metadata for arbitration and diagnostics, not a permission grant.

ADR-015 owns cursor, focus and arbitration semantics; this ADR owns the wire fields.

## Schema authority

The protocol source lives in a neutral `protocol/` directory:

- FlatBuffers IDL for control messages and variable-length input metadata.
- A versioned packed-frame specification for high-frequency pointer movement.
- Generated Swift, TypeScript, and Rust types.
- Shared constants for event names, versions, modifier allowlists, and bounds.

No language owns a hand-edited copy of the schema. Generated files are committed or reproducibly generated at build time. Contract tests must fail if any language drifts.

Packed movement frames are used for pointer *movement* on WebSocket and WebRTC data channels. Every input-critical edge (`pointerDown`, `pointerUp`, `pointerClick`, `pointerCancel`, `scroll`, `keyDown`, `keyUp`, `textInput`, `focusChanged`) travels as a FlatBuffers `Envelope` on a reliable, ordered input-critical channel. Cast uses its compact JSON profile over the text-only custom channel. JSON is not the production pointer format elsewhere.

### Packed movement frame and reliable edge events

`PackedPointerFrame` v12 is a **movement-only** frame: it reports the current pointer position, held-button mask and modifier state. It does not carry press, release, click, cancel or scroll edges. Sending an edge as a packed frame is a protocol error.

| Offset | Field | Type | Endianness | Constraint |
| --- | --- | --- | --- | --- |
| 0 | `frame_magic` | `uint8` | — | `0xA5` for PackedPointerFrame v12 |
| 1 | `event_flags` | `uint8` | — | bits 0–1 phase: `0b00` = move, other values rejected; bits 2–4 current held-button mask; bits 5–7 current modifier state |
| 2–3 | `lease_epoch_lo` | `uint16` | little | Low 16 bits of the active input lease epoch (ADR-015); mismatches are dropped |
| 4–7 | `seq` | `uint32` | little | Per-controller monotonic movement sequence; `seq <= last_seq` is dropped |
| 8–11 | `x_norm` | `float32` | IEEE-754 little | Normalized X in `0...1` |
| 12–15 | `y_norm` | `float32` | IEEE-754 little | Normalized Y in `0...1` |

Movement frames are stateless hints: dropping one is allowed, and the next frame restores the full position and held-state. Button and modifier edges are authoritative and are never inferred from a movement frame.

### Channel-first routing and discriminator

Receivers route **by channel class first** (ADR-010, `transport-mapping.md`):

- Channel 1 carries packed movement frames only.
- Control, runtime, resource and reliable input-critical channels carry FlatBuffers envelopes only.

The `0xA5` check is therefore defense-in-depth on channels that deliberately multiplex, not the primary discriminator. When a channel does multiplex, a frame beginning with `0xA5` is a packed movement frame; anything else is parsed as a FlatBuffers `Envelope` only after its root offset and `file_identifier` are validated. Unknown discriminators are rejected as a typed protocol error. CI fuzzes the FlatBuffers corpus and fails if any valid envelope's first byte is `0xA5` on a multiplexed channel.

### Connection-derived context

The 16-byte movement frame has no `sessionId`, `generation` or `controllerId`. The receiver MUST derive all three from the authenticated transport connection the frame arrived on (ADR-011). A frame arriving on a connection belonging to a previous session or generation is discarded at the transport before the input path sees it. This is why the packed frame needs only `lease_epoch_lo` and `seq`: identity and session binding are properties of the encrypted connection, not of the frame. This rule does not hold on any shared or unauthenticated path, and movement frames are not accepted there.

### Packed-format versioning

The packed format is negotiated on Channel 0 during the session handshake (`input_packed_version`). `0xA5` identifies v12 and is sent only after both peers advertise a supported packed version. A future packed format uses a new magic byte and is never sent before negotiation; a receiver that sees an unnegotiated magic rejects it with a typed protocol error rather than guessing. This keeps the fixed 16-byte frame self-identifying without spending bytes on an in-frame version field.

### Input latency measurement

The packed frame carries no timestamp: at 120 Hz a 16-bit millisecond timestamp wraps in 65 s, and adding a 32-bit timestamp would not fit the 16-byte budget. Instead, input latency is measured with a `LatencyProbe` exchange on Channel 0 (control), timestamped at send and echo. Per-frame latency is derived from the most recent probe; diagnostics MUST NOT claim per-frame timestamps that the wire does not carry.

### FlatBuffers schema evolution and conformance

`protocol/airdesk.fbs` declares `file_identifier "ADEN"`. Every payload MUST be validated with `EnvelopeBufferHasIdentifier()` before table field access.

Schema changes MUST obey these invariants:

1. **Explicit IDs:** every field in `Envelope`, `InputEvent` and `ControlMessage` carries a contiguous `(id: n)` attribute. A union member consumes two slots: the hidden `payload_type` discriminant and the `payload` offset occupy consecutive IDs.
2. **Append-only evolution:** fields and union variants are added at the end or pinned with explicit IDs. Existing fields are never removed or reordered.
3. **Stable defaults:** scalar default values never change after release. Obsolete fields are marked `(deprecated)`, not deleted.
4. **Conformance gate:** `protocol/generate.sh` and the desktop-shell CI workflow run `flatc --conform protocol/baseline/airdesk_v1.fbs protocol/airdesk.fbs` on every pull request. A baseline schema is committed once the first release schema is frozen.
5. **Regeneration:** a schema change regenerates Swift, Rust and TypeScript bindings in the same change; CI fails on generated-output drift.

## Coordinates and viewport

- Pointer `x`/`y` are normalized to `0...1` and validated as finite numbers.
- Viewport `width`/`height` are logical pixels and bounded.
- Display-side transforms convert normalized coordinates to viewport pixels exactly once.
- Missing or invalid coordinates are rejected; they must never default to `0,0`.
- Multi-display or mirrored sessions still use the active desktop viewport, not the phone viewport.
- Persisted window geometry is stored in **logical desktop coordinates** derived from the active `DisplayProfile` (ADR-001), never in phone or preview-sheet pixels.
- Opening, dismissing or resizing `DesktopPreviewSheet` or `MirroredDesktopView` applies a pure CSS/Metal affine transform to the composited surface. Preview presentation must not mutate stored bounds, z-order, focus order or remote surface dimensions.
- Pointer normalization uses the same inverse transform as rendering, so a tap lands at the same logical point at any preview scale.

### Layout portability across display profiles

A workspace may be presented on a different `DisplayProfile` (phone preview, Cast 1080p, external display) without rewriting desired state.

- Stored geometry is normalized to the profile it was authored on, then scaled by the ratio of logical desktop dimensions. Scale factors are clamped to a documented range so a large desktop does not produce unusably small windows on a phone preview.
- Scaled windows are clamped to the visible desktop bounds; a window is never persisted fully off-screen.
- Minimum and maximum window sizes are profile constraints, applied after scaling and recorded as presentation state, not desired state.
- Focus order and z-order are profile-independent: scaling or reflowing must not reorder them.
- If a window cannot be represented without violating a constraint, it is placed in a deterministic fallback position and flagged `relocated` in the recovery/report output rather than silently dropped.
- Layout changes made solely to fit a preview profile are session-local presentation state and are not committed to the manifest.

## Coalescing and ordering

- Pointer moves are coalesced to a 120 Hz cadence with an 8 ms latest-wins window; they are the only traffic allowed on the unreliable packed movement path.
- `pointerDown`, `pointerUp`, `pointerClick`, `pointerCancel`, `scroll`, `keyDown`, `keyUp`, `textInput` and `focusChanged` travel on the reliable input-critical channel and are never coalesced or reordered.
- A drop of a stale pointer move is allowed; a drop of a click, key, or text event is not silently ignored without a recovery rule.
- Sequence numbers are monotonic per session. Generation changes invalidate older frames.
- The receiver rejects stale session/generation frames and ignores duplicate sequence numbers according to ADR-001’s at-most-once rules.
- Acknowledgements are diagnostic/flow-control signals, not permission to replay clicks or keys.

## Click semantics

The normative pointer path is `pointerDown` then `pointerUp`, carrying `clickCount`. The desktop shell synthesizes a single DOM click on release when the gesture qualifies.

`pointerClick` is reserved for sources that cannot supply a reliable down/up pair, such as a constrained Cast sender, an accessibility action, or a test fixture. A source must never send both a `pointerClick` and a down/up pair for the same activation. The receiver must de-duplicate within the gesture window if a malformed or buggy source violates this rule.

This preserves the 11-event vocabulary without creating two activation paths for normal pointer input.

## Validation

The shared validator enforces:

- supported protocol version;
- bounded session identifier and non-negative generation;
- monotonic sequence number;
- finite timestamp;
- normalized coordinates;
- button range `0...4`, click count `1...3`;
- modifier allowlist;
- bounded scroll deltas, key/code lengths, text length, focus target, and viewport dimensions;
- required fields per event type, with malformed frames rejected before dispatch.

Validation errors are diagnostic. They must not crash the shell or trigger a retry storm.

## Acceptance gates

- All 11 events round-trip through Swift, TypeScript, and Rust generated bindings.
- Packed movement frames and FlatBuffers control messages decode identically across languages.
- Channel-first routing sends every edge event on the reliable channel; the `0xA5` check rejects unnegotiated or misplaced packed frames without trial deserialization.
- No valid FlatBuffers envelope in the CI fuzz corpus begins with `0xA5` on a multiplexed channel.
- `flatc --conform` against the frozen baseline schema passes in CI, and generated bindings show zero diff after regeneration.
- Fuzz tests reject malformed, oversized, stale-generation, and duplicate-sequence frames, and reject a packed frame carrying an edge phase.
- A movement frame can be dropped with no lost button, key or scroll edge.
- Latency is measured by the Channel 0 probe; diagnostics do not report per-frame timestamps.
- Coalescing preserves down/up ordering and keeps click/key/text delivery intact.
- One tap produces exactly one activation, whether delivered by down/up or by a constrained-source click.
- Cursor coordinates remain correct after viewport resize, rotation, and external-display changes; no `0,0` regression.
- The 50 ms p95 LAN and 100 ms p95 remote transport budgets from ADR-005 are measured with the canonical schema.
- Reconnect does not replay clicks or keys and does not accept stale-generation input.
- Two controllers can move independent cursors without stealing each other's pointer.
- Keyboard and text events from a non-focus controller are rejected.
- Focus handoff and disconnect release modifiers and pressed buttons on the previous owner.

## Consequences

- One schema and generated bindings replace implicit string contracts and reduce cross-language drift.
- Code generation adds a build step and must be reproducible under ADR-003.
- Packed movement frames improve bandwidth and decode cost, but require a versioned binary specification and fuzzing. Edges cost a FlatBuffers envelope, which is the correct trade for ordering and reliability.
- Restricting `pointerClick` to constrained sources avoids double activation but requires source-specific adapters.
- Cast’s JSON profile remains a separate encoding, so semantic parity tests are mandatory.
- The current `InputEvent` enum and validation code will need migration, but their bounds and failure cases are a useful baseline.

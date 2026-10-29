# ADR-008: Canonical input and control protocol

- **Status:** Proposed — schema generation and contract tests required
- **Date:** 2026-10-29
- **Scope:** Input event vocabulary, schema ownership, coordinates, coalescing, click semantics, session/generation/sequence rules
- **Supersedes:** None
- **Related:** ADR-001, ADR-002, ADR-005, ADR-007

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

## Schema authority

The protocol source lives in a neutral `protocol/` directory:

- FlatBuffers IDL for control messages and variable-length input metadata.
- A versioned packed-frame specification for high-frequency pointer events.
- Generated Swift, TypeScript, and Rust types.
- Shared constants for event names, versions, modifier allowlists, and bounds.

No language owns a hand-edited copy of the schema. Generated files are committed or reproducibly generated at build time. Contract tests must fail if any language drifts.

Packed pointer frames are used on WebSocket and WebRTC. Cast uses its compact JSON profile over the text-only custom channel. JSON is not the production pointer format elsewhere.

## Coordinates and viewport

- Pointer `x`/`y` are normalized to `0...1` and validated as finite numbers.
- Viewport `width`/`height` are logical pixels and bounded.
- Display-side transforms convert normalized coordinates to viewport pixels exactly once.
- Missing or invalid coordinates are rejected; they must never default to `0,0`.
- Multi-display or mirrored sessions still use the active desktop viewport, not the phone viewport.

## Coalescing and ordering

- Pointer moves are coalesced to a 120 Hz cadence with an 8 ms latest-wins window.
- `pointerDown`, `pointerUp`, `pointerClick`, `scroll`, `keyDown`, `keyUp`, and `textInput` are never coalesced or reordered.
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
- Packed pointer frames and FlatBuffers control messages decode identically across languages.
- Fuzz tests reject malformed, oversized, stale-generation, and duplicate-sequence frames.
- Coalescing preserves down/up ordering and keeps click/key/text delivery intact.
- One tap produces exactly one activation, whether delivered by down/up or by a constrained-source click.
- Cursor coordinates remain correct after viewport resize, rotation, and external-display changes; no `0,0` regression.
- The 50 ms p95 LAN and 100 ms p95 remote transport budgets from ADR-005 are measured with the canonical schema.
- Reconnect does not replay clicks or keys and does not accept stale-generation input.

## Consequences

- One schema and generated bindings replace implicit string contracts and reduce cross-language drift.
- Code generation adds a build step and must be reproducible under ADR-003.
- Packed pointer frames improve bandwidth and decode cost, but require a versioned binary specification and fuzzing.
- Restricting `pointerClick` to constrained sources avoids double activation but requires source-specific adapters.
- Cast’s JSON profile remains a separate encoding, so semantic parity tests are mandatory.
- The current `InputEvent` enum and validation code will need migration, but their bounds and failure cases are a useful baseline.

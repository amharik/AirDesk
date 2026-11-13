# SPAKE2+ MVP review promotion — 2026-11-13

## Decision

The product owner accepted the P3-05 review gate for the MVP. This is an
owner-authorized MVP promotion, not an independent third-party cryptographic
audit. The Rust SPAKE2+ surface remains a preview export and is not wired into
product pairing by this decision.

## Reviewed surface

- `core/airdesk-pairing/src/spake2plus.rs`: RFC 9383
  `SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256`, prover/verifier sessions,
  confirmation handling and key schedule.
- `core/airdesk-pairing/src/lib.rs`: AD-PAIR-1 transcript, SAS, scrypt
  registration and fixture-backed evidence.
- `core/airdesk-ffi/src/lib.rs`: typed preview export, generated Swift/Kotlin
  bindings and the iOS FFI smoke test.

## Evidence

- The RFC 9383 P-256 fixture reproduces M/N, `L`, shares, Z/V, transcript,
  confirmation keys, `confirmP`, `confirmV` and `kShared`.
- `confirmV` is validated before the prover releases `confirmP`; the verifier
  validates `confirmP` before completing.
- Confirmation mismatches and post-start failures burn the session, clear
  secrets and reject later transitions.
- P-256 cofactor-1 SEC1 validation rejects off-curve, identity, malformed,
  zero and out-of-range values; confirmation comparison is fixed-length and
  constant-time.
- Zeroization tests cover ephemeral/private scalars, transcripts and session
  key buffers.
- `cargo fmt --check`, strict clippy and the locked core workspace test suite
  pass, including the pairing vector, wrong-role/out-of-order, mismatch-burn and
  malformed-point cases.

## Residuals

- External independent review is still recommended before general production
  cutover, long-term interoperability guarantees, or removal of the native
  pairing path.
- The preview export is non-authoritative. Product pairing continues to use the
  existing reviewed path until a separate cutover is approved and tested.
- No claim is made that vector equality alone proves side-channel resistance,
  protocol composition safety or implementation independence.

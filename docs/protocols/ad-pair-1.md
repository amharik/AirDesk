# AD-PAIR-1 pairing transcript and key schedule

Status: partial implementation behind [ADR-011](../adr/011-device-identity-discovery-pairing.md). The transcript, signature checks, channel-binding validation and key schedule are implemented in the browser identity layer. An interactive RFC 9383 SPAKE2+ P-256 prover/verifier session is implemented, validated against the RFC vector and integrated with `AdPairSession` confirmation evidence. An scrypt password PBKDF, salted registration record and browser QR/PIN challenge envelopes are implemented. The camera/UI flow, native parity and native/browser binding acquisition remain pending.

## Scope

AD-PAIR-1 binds a pairing offer, a pairing response and the PAKE evidence into one canonical transcript. Both devices sign that transcript with their long-term device identity. The resulting hash seeds the SAS and session-key schedule.

It does not establish trust by itself. The offer still needs nonce, expiry and replay validation, and the user still needs to confirm the SAS or PIN.

## Canonical transcript

```text
"AD-PAIR-1\n" + UTF-8(JSON)
```

The JSON object contains:

- `domain`: `"AD-PAIR-1"`
- `protocol` and `version`
- the normalized channel binding
- canonical offer and response payloads
- normalized PAKE evidence

Canonical payloads sort `capabilities`, preserve optional fields as `null`, and normalize the channel binding. Both payloads must carry a supported binding of the same kind and value.

PAKE evidence fields are `initiatorShare`, `responderShare`, `initiatorConfirmation` and `responderConfirmation`. Each is base64url and must decode to 16–1024 bytes.

## Channel binding

Accepted kinds:

| Kind | Value |
| --- | --- |
| `certificate-hash` | Lowercase 64-character SHA-256 hex |
| `exporter` | Base64url TLS exporter value, at least 16 bytes |

`none`, unknown kinds, mismatched bindings and malformed values fail closed. The browser does not yet acquire either binding from a real pairing transport.

## Signatures

Each side signs the canonical transcript bytes with its device key. Ed25519 is the default; P-256 is the fallback. Verification uses the public key from the validated pairing payload and rejects an empty signature, wrong device identity, malformed signature or invalid signature.

## SPAKE2+ primitive

`web/src/identity/spake2plus.ts` implements the RFC 9383 P-256/SHA-256/HKDF-SHA-256/HMAC-SHA-256 flow:

- prover and verifier shares, registration record `L = w1*P`, and the `Z`/`V` values
- the exact RFC transcript with 8-byte little-endian length prefixes
- `K_main`, `K_confirmP`, `K_confirmV`, `K_shared`, and confirmation tags
- point decoding, identity rejection, subgroup checks, scalar-range checks and constant-time confirmation comparison

`web/test/spake2plus.test.ts` reproduces the RFC 9383 P-256 test vector, including `shareP`, `shareV`, `Z`, `V`, `TT`, all derived keys and both confirmations. The primitive requires canonical registration scalars and uses `@noble/curves` for point arithmetic.

`Spake2PlusSession` adapts the primitive to the interactive exchange: `proverStart()` emits the prover share, `verifierRespond()` returns the verifier share and confirmation, `proverFinish()` verifies the verifier confirmation and emits the prover confirmation, and `verifierFinish()` verifies the prover confirmation. The resulting base64url shares, confirmations and shared secret can be supplied to `AdPairSession` as `pakeExchange`; `AdPairFinishInput.secret` is then optional, and the session validates the exchange before signing the transcript.

Native parity is still required before pairing can be called complete.

## Password PBKDF

`deriveSpake2PlusPasswordScalars()` and `createSpake2PlusPasswordRegistration()` implement the RFC 9383 password-to-scalar step:

- password strings are normalized with NFKC; empty passwords are rejected
- the material is `len(password) || password || len(idProver) || idProver || len(idVerifier) || idVerifier`
- scrypt uses `N=32768`, `r=8`, `p=1`, `dkLen=80` and a 16–64 byte salt; generated salts are 32 bytes
- the two 40-byte halves are reduced modulo the P-256 order to produce `w0` and `w1`
- the registration record is `L = w1*P`; the salt and profile must travel with the registration record

## QR/PIN challenges

`web/src/identity/pairing-code.ts` defines the `ADPAIR1:` QR envelope and PIN/QR-secret challenge flow:

- the QR code carries a validated ADFP offer, a pairing mode (`pin` or `qr-secret`), and a 16–64 byte salt; it never carries a PIN or long-term secret
- PIN mode generates an unbiased six-digit PIN for display/entry on the host and controller
- QR-secret mode carries a short-lived 16–64 byte random secret in the QR code, avoiding PIN entry
- both sides derive the SPAKE2+ registration with `w0`/`w1` from the PIN or secret, salt and both device IDs; the host needs only `w0` and `L`
- PIN attempts are limited in memory and fail closed on expiry or lockout
- malformed modes, salts, identities, unknown fields, expired offers and replayed nonces are rejected

The camera/scanning UI and native parity are pending. A QR code is a bootstrap carrier, not a trust decision; the AD-PAIR-1 transcript, signatures and channel binding still have to validate.

## SAS

```text
digest = SHA-256("AD-PAIR-1-SAS\n" || transcriptHash)
SAS = decimal(digest[0..4] as big-endian uint32 mod 1_000_000), zero-padded to six digits
```

The SAS is only a user-comparison value. It is not a session key and does not replace SPAKE2+ confirmation.

## Key schedule

```text
schedule = "AD-PAIR-1-KS"
version = 1
KDF = HKDF-SHA256
salt = transcriptHash
IKM = PAKE shared secret (16–1024 bytes)
info = UTF-8(JSON)
```

The `info` object contains the schedule domain, version, output label, channel binding and transcript hash in hex. Outputs are 32 bytes each:

| Purpose | Label |
| --- | --- |
| Initiator to responder | `i2r` |
| Responder to initiator | `r2i` |
| Transport | `transport` |

The transcript hash must be exactly 32 bytes. Missing or malformed channel bindings fail before key derivation.

## Test fixture

`web/test/fixtures/ad-pair-1.json` fixes the transcript and key-schedule vectors. `web/test/identity-pairing.test.ts` covers signatures, binding mismatch, replay/expiry, SAS and session keys.

## Pending

- QR/PIN camera/scanning UI, native parity and user-verification integration.
- TLS exporter and browser host-certificate hash acquisition.
- Native iOS/Android implementation and cross-platform vectors.
- Transport binding of the derived keys to ADFP or Iroh.

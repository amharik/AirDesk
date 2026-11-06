# AD-PAIR-1 pairing transcript and key schedule

Status: partial implementation behind [ADR-011](../adr/011-device-identity-discovery-pairing.md). The transcript, signature checks, channel-binding validation and key schedule are implemented in the browser identity layer. SPAKE2+ itself, QR/PIN flows and native/browser binding acquisition remain pending.

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

- RFC 9383 SPAKE2+ P-256 share generation, confirmation verification and shared-secret validation.
- QR/PIN acquisition and user-verification flows.
- TLS exporter and browser host-certificate hash acquisition.
- Native iOS/Android implementation and cross-platform vectors.
- Transport binding of the derived keys to ADFP or Iroh.

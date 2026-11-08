# ADR-022: OpenSSL P-256 group arithmetic for native AD-PAIR-1

- **Status:** Accepted — native SPAKE2+ adapter implemented
- **Date:** 2026-11-07
- **Deciders:** Engineering lead, security owner
- **Scope:** iOS pairing cryptography, dependency admission, native/browser parity
- **Supersedes:** None
- **Amends:** ADR-003 dependency admission for the OpenSSL binary distribution; ADR-011 native AD-PAIR-1 implementation
- **Amended by:** ADR-023 OpenSSL scrypt for native SPAKE2+ password registration
- **Related:** ADR-011, ADR-012, ADR-021, ADR-023

## Context

The browser implements RFC 9383 SPAKE2+ over P-256, including arbitrary scalar multiplication, point addition and subtraction. Apple CryptoKit exposes P-256 key generation, ECDH, signatures and hashing, but it does not expose the group operations needed to compute `x*P + w0*M`, `S - w0*N`, `y*S` or `y*L`.

Implementing P-256 field and group arithmetic in AirDesk would create a new security-critical cryptographic primitive with no independent audit. Using a different curve or changing the AD-PAIR-1 suite would break browser/native interoperability.

## Decision

Use the existing audited OpenSSL 3.x implementation through the `OpenSSL` SwiftPM binary distribution at `https://github.com/krzyzanowskim/OpenSSL-Package.git`, pinned to `3.6.5000` (OpenSSL 3.6.5).

The dependency is admitted only for P-256 group arithmetic:

- the adapter is isolated in `NativeP256Group` and `Spake2PlusP256`;
- CryptoKit remains the source for SHA-256, HMAC, HKDF and AES-GCM;
- OpenSSL is not used as a TLS stack, identity store or general-purpose crypto API;
- the browser keeps its existing WebCrypto/noble implementation;
- the Android implementation remains independent.

## Admission evidence

| Gate | Evidence |
| --- | --- |
| License | OpenSSL 3.x is Apache-2.0; the SwiftPM distribution declares Apache-2.0 and ships OpenSSL notices |
| Maintenance | OpenSSL is an actively maintained upstream security project; `krzyzanowskim/OpenSSL-Package` is the maintained SwiftPM distribution |
| Security reporting | OpenSSL security policy and release process apply to the pinned upstream version |
| Platform fit | Prebuilt XCFramework supports iOS 17.5, simulator and device slices |
| Upstream evidence | Pinned OpenSSL 3.6.5 release; the AirDesk tests validate the RFC 9383 P-256 vector and the browser AD-PAIR-1 fixture |
| AirDesk evidence | `NativeP256Tests` covers encoding, scalar range and malformed points; `Spake2PlusP256Tests` reproduces the RFC 9383 shares, `Z`, `V`, transcript, keys and confirmations; full iOS suite passes |
| Supply chain | Exact SwiftPM version and package checksum; framework slice is approximately 4.9 MB (`ios-arm64`) |
| Exit strategy | Remove the adapter if CryptoKit exposes full P-256 point arithmetic or a narrower audited P-256 group package is admitted |

## Consequences

- Native AD-PAIR-1 can reproduce the browser SPAKE2+ exchange without a protocol fork.
- The iOS binary gains the pinned OpenSSL framework slice and must include OpenSSL attribution.
- Future OpenSSL upgrades require a new exact pin and a repeat of the RFC/browser vector tests.
- OpenSSL is not a general-purpose dependency: new uses require an ADR-003 review.
- Native password-to-scalar scrypt registration is admitted separately by ADR-023; native PIN/QR pairing and SAS are implemented, while browser certificate/exporter binding acquisition remains implementation work under ADR-011.

## Validation

`Spake2PlusP256Tests` reproduces the RFC 9383 vector:

- `M` and `N` compressed constants, registration record `L`, prover share `shareP`, verifier share `shareV`, `Z`, `V`, transcript `TT`, `K_main`, `K_confirmP`, `K_confirmV`, `K_shared`, `confirmP` and `confirmV`;
- prover and verifier sessions accept matching confirmations and derive the same shared key;
- tampered confirmations and malformed/off-curve points fail closed.

# ADR-023: OpenSSL scrypt for native SPAKE2+ password registration

- **Status:** Accepted — native password registration implemented
- **Date:** 2026-11-07
- **Deciders:** Engineering lead, security owner
- **Scope:** iOS pairing cryptography, password registration, native/browser parity
- **Supersedes:** None
- **Amends:** ADR-003 dependency admission and ADR-022 OpenSSL use for native AD-PAIR-1
- **Related:** ADR-011, ADR-012, ADR-022

## Context

RFC 9383 maps a password or PIN to the SPAKE2+ registration scalars `w0` and `w1` with scrypt. The browser already implements the profile `N=32768`, `r=8`, `p=1`, `dkLen=80` and reduces each 40-byte half modulo the P-256 order. Native pairing must reproduce that profile byte-for-byte so a PIN registered on one platform can complete pairing on the other.

CryptoKit does not expose scrypt. Writing a new password-based key-derivation function in AirDesk would create another security-critical primitive without independent review.

## Decision

Use the OpenSSL 3.6.5 `EVP_PBE_scrypt` implementation from the dependency already admitted by ADR-022, pinned through `OpenSSL-Package` `3.6.5000`.

The use is limited to native SPAKE2+ password registration:

- the profile is fixed at `N=32768`, `r=8`, `p=1`, `dkLen=80`, with a 16–64 byte salt and a 64 MiB memory ceiling;
- password strings are normalized with NFKC and encoded as UTF-8;
- the scrypt input is the browser-compatible length-prefixed `password || idProver || idVerifier` material;
- each 40-byte output half is reduced modulo the P-256 group order, and a zero `w1` is rejected;
- the registration record remains `L = w1*P` through `NativeP256Group`;
- OpenSSL is still not used as a TLS stack, identity store or general-purpose crypto API;
- Android remains independent.

## Admission evidence

| Gate | Evidence |
| --- | --- |
| License | Same Apache-2.0 OpenSSL 3.6.5 distribution admitted by ADR-022 |
| Maintenance | Same actively maintained upstream and SwiftPM distribution |
| Platform fit | Same pinned XCFramework; no new dependency or binary slice |
| Upstream evidence | OpenSSL `EVP_PBE_scrypt` implements the standard scrypt KDF |
| AirDesk evidence | `Spake2PlusP256Tests` matches a Node/OpenSSL scrypt fixture for the canonical password material, `w0`, `w1`, salt handling and registration record; the full iOS suite passes |
| Exit strategy | Replace the call if CryptoKit exposes scrypt or a narrower audited scrypt package is admitted |

## Consequences

- Native PIN registration interoperates with the browser profile without a protocol fork.
- The same OpenSSL attribution, pinning and upgrade-review requirements as ADR-022 apply.
- A new OpenSSL use requires an ADR-003 review; this ADR admits only scrypt password derivation.
- Native PIN/QR pairing and SAS are implemented; browser certificate/exporter channel binding remains implementation work under ADR-011.

## Validation

`Spake2PlusP256Tests` covers:

- the canonical password material vector;
- the known cross-platform `w0`/`w1` fixture for `correct horse battery staple`, a 32-byte salt and `client`/`server` identities;
- salt, password and identity binding;
- 16–64 byte salt bounds and empty-password rejection;
- derived registration records and an interactive prover/verifier session using password-derived scalars.

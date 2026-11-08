# ADR-011: Device identity, discovery and secure pairing

- **Status:** Proposed — pairing and platform qualification gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — device trust separated from workspace ownership and user identity
- **Updated:** 2026-11-03 — peer review: RFC 9383 SPAKE2+ pairing bound to the TLS 1.3 exporter
- **Updated:** 2026-11-03 — peer review round 3: browser pairing binds the host certificate hash; canonical DNS-SD records and TXT keys
- **Updated:** 2026-11-07 — native SPAKE2+, scrypt registration and the canonical transcript/signature/session flow reproduce the browser fixture; live binding/UI remain pending
- **Deciders:** Security owner, engineering lead
- **Scope:** Device keys, identity lifecycle, local discovery, QR pairing, session authentication, revocation, trust boundaries
- **Supersedes:** None
- **Related:** ADR-001, ADR-005, ADR-009, ADR-010, ADR-012, ADR-013, ADR-014, ADR-015, ADR-016, ADR-018

## Context

The device-fabric release needs a pairing path that works without a central account and without assuming that multicast discovery works on the target network. Native and future browser endpoints need stable identities that survive address changes.

The pairing design must also work with iOS background restrictions and browser permission and secure-context rules.

## Decision

### 1. Device identity is cryptographic and stable

Each AirDesk device generates a persistent key pair.

- Ed25519 is the default application identity algorithm.
- P-256 is the fallback where Ed25519 is unavailable, including browser profiles without Ed25519 WebCrypto support and hardware-backed native keys where required.
- The private key is stored in the Keychain with appropriate access control.
- Secure Enclave does not provide Ed25519 signing keys; a hardware-backed P-256 key or a hardware-backed wrapping key is used rather than claiming Ed25519 Secure Enclave support.
- The public key fingerprint is the device identity anchor.
- The `deviceId` is a random identifier derived from or bound to the public key, not a device name, IP address or user-visible label.
- Device display names are metadata and are not trusted for authorization.
- Keys support rotation, revocation and lost-device recovery.

No account login is required for local pairing in v1. Cloud identity and cross-device account sync are separate future decisions.

### 1.1 Device trust is not workspace ownership

- A paired device is trusted to participate, not to own the workspace.
- Device identity is not a user identity and not a workspace owner identity.
- Pairing does not grant workspace membership, collaboration rights or optional capabilities.
- Workspace ownership belongs to the workspace model in ADR-016.
- A controller attachment is a session role, not workspace ownership.
- Future user identity, workspace membership and roles require a separate decision.
- Revoking a device invalidates its trust and session credentials; it does not delete the workspace.

### 1.2 Future user identity uses WebAuthn/FIDO2, not device keys

When AirDesk adds account or multi-user identity, use WebAuthn/FIDO2 as the user-authentication reference:

- A passkey or platform authenticator proves user identity to a relying party.
- The user handle is opaque and separate from device names, device IDs and public-key fingerprints.
- User verification is requested explicitly; user presence and user verification are not treated as equivalent.
- Synced and device-bound credentials are distinguishable for policy.
- Device identity remains the transport and capability-trust anchor. A user credential does not automatically grant device trust, and device trust does not prove user identity.
- Workspace ownership and membership reference user identity, not a device identity.

Local v1 pairing still requires no account.

### 2. Discovery is layered

| Path | Use | Notes |
| --- | --- | --- |
| QR pairing | Universal fallback and endpoint bootstrap | Required for the device fabric and browser endpoint |
| Bonjour/DNS-SD | Native local discovery | Optional adapter, never required |
| Authenticated rendezvous | Browser or cross-network discovery | Future; must not be required for LAN use |
| Nearby Connections / Wi-Fi Aware | Optional native proximity adapters | Deferred until measured need |

Do not require mDNS for correctness. Browser endpoints use QR or an authenticated rendezvous because browser multicast discovery is restricted.

### 3. DNS-SD advertises minimal information

The canonical service records are:

- `_airdesk._tcp.local.` — control endpoint (TLS WebSocket), advertised whenever mDNS is enabled.
- `_airdesk._udp.local.` — optional WebTransport/QUIC hint, advertised only when a WebTransport listener is running.

Canonical TXT keys:

```text
txtvers=1
adfp_ver=1.0
device_type=host|controller|display
certhash_current=<sha256>
certhash_next=<sha256>
```

`device_type` is coarse. The DNS-SD instance name is a random per-boot label, not a stable device identifier.

Do not advertise:

- a stable device ID (`dev_id`) or role bitmask (`role_mask`);
- authentication tokens;
- private paths;
- capability details;
- user names;
- camera, microphone or filesystem availability;
- anything that enables fingerprinting or capability inference before authentication.

Detailed capabilities and stable identities are exchanged only after authenticated pairing. The `certhash_*` values are certificate hashes, not identities; they are accepted only as described in section 4.2.

### 4. QR pairing is an authenticated bootstrap

A pairing QR code contains only what is needed to begin a session:

- protocol version;
- ephemeral public key;
- random nonce;
- expiry;
- endpoint hint or rendezvous reference;
- optional relay hint.

The QR code must not contain reusable long-term secrets.

Pairing sequence:

1. The receiver displays a short-lived QR code.
2. The controller scans it and verifies the protocol and expiry.
3. Both sides perform an authenticated ephemeral key exchange.
4. Both sides display or compare a short authentication fingerprint where practical.
5. The device is added to the workspace with explicit capability grants.
6. A short-lived session credential is issued.

Pairing transcript:

- The password-authenticated exchange is RFC 9383 SPAKE2+ over P-256 for browser/native interoperability (section 4.1).
- The transcript hash binds `protocol_version`, initiator and responder device IDs, both SPAKE2+ shares and confirmation tags, nonces, expiry, endpoint hints and requested capabilities with SHA-256.
- The transcript binds a channel-binding value: the TLS exporter `EXPORTER-AirDesk-Pairing-v1` when both peers are native and can read it, otherwise the host certificate hash delivered out of band (section 4.2). It is never left unbound.
- Each side signs the transcript with its long-term Ed25519 key, or its P-256 key when that is the device identity.
- The short authentication string is a truncated hash of the completed transcript and is compared out of band where a display is available.
- Session keys are derived from the SPAKE2+ secret, the channel-binding value and the transcript hash; long-term private keys never leave their device.

The flow rejects expired nonces, replayed QR codes, transcript mismatches, invalid signatures and mismatched fingerprints.

The flow is named **AD-PAIR-1**. It is one construction, not a family of loosely specified pairing modes.

### 4.1 PIN and QR pairing use SPAKE2+ (RFC 9383)

AD-PAIR-1 uses RFC 9383 SPAKE2+ for the PIN/QR password-authenticated exchange. SPAKE2+ is augmented: only the host stores the verifier, so a compromised controller cannot impersonate the host without the PIN.

- The password is the short-lived 6-digit PIN or the secret carried in the QR payload. It is never transmitted.
- The group is P-256 for browser/native interoperability; the SPAKE2+ identity fields are `initiator` / `responder` domain-separated with the ADFP protocol version and both device IDs.
- When both peers are native, the exchange is bound to the established TLS 1.3 connection through the keying-material exporter with label `EXPORTER-AirDesk-Pairing-v1` and the pairing transcript as context. A relay that terminates TLS on a different connection cannot complete the exchange.
- The channel-binding value and the SPAKE2+ confirmation keys are mixed into the session-key derivation; the short authentication string is derived from the combined transcript.
- Failed attempts are rate-limited; the PIN expires after a short window and after a bounded number of attempts.
- The transcript, confirmation tags and key schedule are specified with test vectors before implementation.

An active MITM relay that forwards bytes between two TLS connections cannot produce the same exporter value on both legs, so binding the SPAKE2+ transcript to the exporter closes the relay attack that SPAKE2+ alone does not.

### 4.2 Browser endpoints bind to the host certificate hash instead of the exporter

Web browsers do not expose TLS keying-material exporters to JavaScript, and WKWebView does not expose them to the page either. A browser/native pairing therefore cannot use `EXPORTER-AirDesk-Pairing-v1`. The rule is:

- If either peer is a browser (including the WKWebView shell), the host's TLS certificate SHA-256 is carried out of band in the QR payload or the authenticated rendezvous response, and that hash is mixed into the pairing transcript.
- The hash must come from the pairing payload or a signed advertisement. A hash observed from the live connection, from mDNS alone, or from an unsigned redirect is not accepted; accepting it would let a relay substitute its own certificate.
- The browser verifies the server certificate matches the out-of-band hash before the SPAKE2+ exchange (WebTransport `serverCertificateHashes`, WebSocket via the native shell's pinned-certificate policy).
- Native peers continue to bind the exporter and may additionally bind the certificate hash. The transcript records which binding was used so the two sides cannot silently disagree.
- A pairing attempt that presents no acceptable binding is rejected; there is no "unbound" mode.

This closes the same relay attack for browser endpoints while remaining implementable in WebKit.

### 5. Transport security is not reimplemented

Use TLS 1.3 or DTLS as provided by the selected transport. Use application-level device authentication and capability grants to authorize actions.

Do not layer Noise over DTLS merely for defense in depth unless a specific libp2p adapter requires it.

No plaintext LAN fallback is permitted.

### 6. Browser constraints are explicit

- Browser camera, microphone, clipboard and local-network access require user permission.
- Some APIs require HTTPS or a secure context.
- A browser receiver may not be able to scan a QR code; the phone scans the receiver's code.
- A browser cannot be assumed to be an always-on workspace server.
- Browser private keys must be non-extractable where supported and are stored in IndexedDB or OPFS.
- Browser storage may be evicted; eviction loses the browser identity and requires re-pairing.
- The app must surface re-pairing explicitly and must not silently rotate the browser identity.
- A browser identity is scoped to one browser profile on one device; it is not an account identity.

If the browser endpoint cannot satisfy secure-context or hosting requirements, the external-display path remains the fallback MVP.

### 7. iOS background limits are part of the model

AirDesk must not promise persistent peer availability while the iOS app is suspended. Session reconnection follows application lifecycle events. Long-lived workspace availability requires a host, browser endpoint or receiver that is allowed to remain active.

### 8. Revocation and audit are required

- A paired device can be revoked.
- Revocation invalidates session credentials and capability grants.
- Lost-device recovery requires a local confirmation flow, not a display-name lookup.
- Pairing and revocation events are auditable locally.

## Consequences

### Positive

- Pairing does not require an account or a cloud dependency.
- Device identity survives IP and network changes.
- QR provides a cross-platform fallback.
- Capability grants are tied to authenticated devices.

### Negative

- Key storage, rotation and recovery add implementation work.
- QR pairing alone does not provide remote connectivity.
- Bonjour and browser discovery differ significantly.
- Native proximity transports add SDK and lifecycle burden.

## Acceptance gates

- AD-PAIR-1 succeeds between a supported controller and a native agent or browser endpoint with Ed25519 identities, or P-256 where Ed25519 is unavailable.
- AD-PAIR-1 uses RFC 9383 SPAKE2+ over P-256 and binds the transcript to `EXPORTER-AirDesk-Pairing-v1` for native/native pairs; a relay that terminates two different TLS connections cannot complete pairing.
- Browser/native pairing binds the host certificate SHA-256 from the pairing payload or signed advertisement (no browser exporter is assumed); a certificate hash taken only from the live connection or unsigned mDNS is rejected.
- An unbound pairing attempt is rejected; the transcript records which binding was used.
- Expired, replayed or transcript-mismatched QR codes are rejected; failed PIN attempts are rate-limited and the PIN expires.
- A revoked device cannot establish a new session or use existing grants.
- Pairing alone does not grant workspace ownership, membership or optional capabilities.
- Device trust, workspace ownership and controller attachment are represented by separate identifiers.
- DNS-SD records contain no tokens, private paths or capability details.
- Pairing works when mDNS is unavailable.
- No plaintext LAN session path exists.
- iOS suspension behavior is documented and tested.
- Browser permission and secure-context limitations are reported truthfully.
- Browser identity storage eviction produces an explicit re-pair flow and no silent key rotation.
- Pairing transcript construction, signature inputs and session-key derivation are specified and have test vectors.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Account-based identity | Requires a cloud service and breaks offline-first pairing |
| Trust-on-first-use without a PIN or QR secret | Gives no protection against an active MITM |
| Plain SPAKE2+ without a channel binding | A TLS-terminating relay can complete two independent exchanges |
| SPAKE2+ plus TLS exporter or out-of-band certificate hash | Chosen: password-authenticated, offline, and bound to the real channel in both native and browser cases |
| Noise layered over TLS | Adds complexity without a named threat the TLS binding does not cover |

## Out of scope

- Account identity and cloud login in v1.
- WebAuthn/FIDO2 implementation before a user-identity release.
- Cross-network rendezvous and TURN relay.
- Multi-user group membership.
- libp2p as a required identity layer.
- Nearby Connections or Wi-Fi Aware implementation.

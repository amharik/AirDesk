# ADR-011: Device identity, discovery and secure pairing

- **Status:** Proposed — pairing and platform qualification gates required
- **Date:** 2026-11-03
- **Scope:** Device keys, identity lifecycle, local discovery, QR pairing, session authentication, revocation
- **Supersedes:** None
- **Related:** ADR-001, ADR-005, ADR-009, ADR-010, ADR-012, ADR-013

## Context

The browser-first MVP needs a pairing path that works without a central account and without assuming that multicast discovery works on the target network. Future native devices need stable identities that survive address changes.

The pairing design must also work with iOS background restrictions and browser permission and secure-context rules.

## Decision

### 1. Device identity is cryptographic and stable

Each AirDesk device generates a persistent Ed25519 key pair.

- The private key is stored in the Keychain with appropriate access control.
- Ed25519 is the application identity algorithm. Secure Enclave does not provide Ed25519 signing keys; where hardware-backed protection is required, use a P-256 key or a hardware-backed wrapping key instead of claiming Ed25519 Secure Enclave support.
- The public key fingerprint is the device identity anchor.
- The `deviceId` is a random identifier derived from or bound to the public key, not a device name, IP address or user-visible label.
- Device display names are metadata and are not trusted for authorization.
- Keys support rotation, revocation and lost-device recovery.

No account login is required for local pairing in v1. Cloud identity and cross-device account sync are separate future decisions.

### 2. Discovery is layered

| Path | Use | Notes |
| --- | --- | --- |
| QR pairing | Universal fallback and browser bootstrap | Required for the browser-first MVP |
| Bonjour/DNS-SD | Native local discovery | Optional adapter, never required |
| Authenticated rendezvous | Browser or cross-network discovery | Future; must not be required for LAN use |
| Nearby Connections / Wi-Fi Aware | Optional native proximity adapters | Deferred until measured need |

Do not require mDNS for correctness. Browser endpoints use QR or an authenticated rendezvous because browser multicast discovery is restricted.

### 3. DNS-SD advertises minimal information

Advertise only a service record and coarse metadata, for example:

```text
_airdesk._tcp
protocol=1
device_type=host
security=required
```

Do not advertise:

- authentication tokens;
- private paths;
- capability details;
- user names;
- camera, microphone or filesystem availability;
- anything that enables fingerprinting before authentication.

Detailed capabilities are exchanged only after authenticated pairing.

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
3. Both sides perform an authenticated key exchange.
4. Both sides display or compare a short authentication fingerprint where practical.
5. The device is added to the workspace with explicit capability grants.
6. A short-lived session credential is issued.

The flow rejects expired nonces, replayed QR codes and mismatched fingerprints.

### 5. Transport security is not reimplemented

Use TLS 1.3 or DTLS as provided by the selected transport. Use application-level device authentication and capability grants to authorize actions.

Do not layer Noise over DTLS merely for defense in depth unless a specific libp2p adapter requires it.

No plaintext LAN fallback is permitted.

### 6. Browser constraints are explicit

- Browser camera, microphone, clipboard and local-network access require user permission.
- Some APIs require HTTPS or a secure context.
- A browser receiver may not be able to scan a QR code; the phone scans the receiver's code.
- A browser cannot be assumed to be an always-on workspace server.

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

- QR pairing succeeds between the supported controller and browser endpoint.
- Expired or replayed QR codes are rejected.
- A revoked device cannot establish a new session or use existing grants.
- DNS-SD records contain no tokens, private paths or capability details.
- Pairing works when mDNS is unavailable.
- No plaintext LAN session path exists.
- iOS suspension behavior is documented and tested.
- Browser permission and secure-context limitations are reported truthfully.

## Out of scope

- Account identity and cloud login.
- Cross-network rendezvous and TURN relay.
- Multi-user group membership.
- libp2p as a required identity layer.
- Nearby Connections or Wi-Fi Aware implementation.

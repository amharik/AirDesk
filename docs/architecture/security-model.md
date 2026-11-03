# Security model

AirDesk coordinates devices with different operating systems, permissions and trust levels. The security model must remain truthful about those differences.

## Identities

- **Workspace identity:** stable logical workspace; independent of devices and sessions.
- **User identity:** local personal identity initially; multi-user identity later.
- **Device identity:** long-lived key associated with a device.
- **Session identity:** credentials for one display or controller session.
- **Runtime identity:** provider instance identity; not a workspace identity.

Device keys use Ed25519 by default. WebCrypto/platform P-256 is a documented fallback. Private keys remain in platform secure storage where available.

## Pairing and trust

Pairing establishes device trust. It does not grant:

- workspace ownership;
- workspace membership;
- collaboration rights;
- optional capability access;
- display or controller authority.

Discovery is not trust. A discovered device is untrusted until pairing succeeds.

## Capability authorization

Every sensitive operation requires an explicit capability lease. Authorization considers device trust, workspace, application, user consent, scope, expiry, platform permission and revocation state.

Revocation is separate from disconnect. Disconnecting a device does not necessarily revoke it; revoking a device invalidates its trust and outstanding leases.

## Transport security

- Control and remote data require authenticated encryption.
- Loopback is not automatically trusted; local origin checks still apply.
- WebRTC DTLS fingerprints must be bound to authenticated device or session identity.
- Relay is an encrypted fallback, not a silent substitute for a failed direct path.
- Browser endpoints require secure contexts and cross-origin isolation where needed.

## Coordinator

The coordinator may provide discovery assistance, rendezvous, signaling and encrypted relay. It must not:

- own workspace authority;
- hold user device private keys;
- silently read payload content;
- mint capability grants or leases;
- make a local workspace dependent on cloud connectivity.

## Application isolation

- Runtime providers enforce their own isolation.
- Capability access goes through the host ABI and leases.
- Browser endpoints run untrusted code and must not receive unrestricted host access.
- Remote execution requires explicit placement and authorization.
- Secrets must not be stored in workspace manifests or logs.

## Threats to test

- Cross-site WebSocket hijacking.
- Malicious QR/pairing payload.
- Replay of pairing or revocation messages.
- Stolen device key.
- Forged capability lease.
- Stale revocation acceptance.
- Hosted browser endpoint impersonation.
- Cross-workspace controller reuse.
- Relay traffic analysis and unauthorized payload access.

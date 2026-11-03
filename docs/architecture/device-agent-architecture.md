# Device agent architecture

A device agent is the native integration point between AirDesk and a platform operating system.

## Contract

```text
DeviceAgent
  identity()
  capabilities()
  requestCapability(cap_uri, request)
  releaseCapability(leaseId)
  subscribe(eventType, handler)
  health()
```

The contract is logical. Components in the same process may call it directly; remote components use ADFP.

The canonical contract is `CapabilityHostABI`. The device agent and Wanix provider are adapters around it, not competing authorities.

## Wanix boundary

Wanix exposes a unified per-process namespace. Tasks are driven by namespaced file-service interfaces; host-exported devices and `#web` services are the host boundary. A native agent maps `CapabilityHostABI` onto that boundary:

- capability requests become scoped file-service or exported-device operations;
- leases are enforced before any host bind is exposed;
- event subscriptions become namespace reads or callbacks;
- a remote Wanix namespace can be imported over 9P/WebSocket without granting workspace authority.

AirDesk does not assume an undocumented public “host command namespace.” Where Wanix lacks a stable interface, the adapter implements one inside AirDesk and keeps it versioned.

## Platform responsibilities

- Device identity and key storage.
- Capability advertisement.
- Camera, microphone, filesystem, sensor and input permissions.
- Native keyboard and pointer events.
- Notifications.
- Native process and application integration.
- Display and external-scene integration.
- Network and background constraints.
- Health and lifecycle reporting.

## Capability host ABI

A runtime provider accesses host functionality only through an explicit adapter:

```text
CapabilityHostABI
  request(leaseId, operation, arguments)
  release(leaseId)
  subscribe(leaseId, eventType, handler)
```

- The adapter enforces capability leases and platform permissions.
- It must not provide unrestricted filesystem, process or device access.
- A Wanix-backed adapter may expose only an explicit, scoped namespace subtree.
- It is versioned independently of ADFP wire versions and runtime versions.
- Unsupported operations fail closed with a typed error.

The normative ABI is the WASI 0.2 Component Model package `airdesk:host-abi@0.1.0`, expressed in WIT and layered on `wasi:io/streams@0.2.0`, `wasi:filesystem/types@0.2.0` and `wasi:cli/run@0.2.0`. It defines at least:

- `vfs-service` for AD-RESOURCE mounts, with path canonicalization and no `..` escape;
- `pty-service` for AD-RUNTIME PTY sessions with a 256 KiB credit window;
- `display-sink` for AD-DISPLAY/ADR-014, guarded by `OriginPolicy` and the active `leaseEpoch`.

The same WIT-defined capability component runs in Wanix in the browser and in the native Rust/Swift agent. Capability tokens are `COSE_Sign1` and are validated on every host call.

## Native execution

Native execution is first-class. It covers native applications, platform APIs, hardware acceleration, background tasks and platform-specific integrations. A device is useful without Wanix.

## Browser agents

A browser endpoint is a presentation consumer. It may hold a browser identity and request scoped capabilities, but it is not a native agent and does not bypass platform or browser permissions. It starts with a single-threaded Wanix profile and upgrades to threaded execution only after cross-origin isolation checks.

## Agent failure

- Agent disconnect makes its capabilities unavailable.
- Leases associated with the agent are revoked or expired.
- Workspace definitions remain.
- The orchestrator reconciles when the agent returns.
- A stale agent identity or revoked device is rejected.

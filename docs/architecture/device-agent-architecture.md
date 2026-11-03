# Device agent architecture

A device agent is the native integration point between AirDesk and a platform operating system.

## Contract

```text
DeviceAgent
  identity()
  capabilities()
  requestCapability(capabilityId, request)
  releaseCapability(leaseId)
  subscribe(eventType, handler)
  health()
```

The contract is logical. Components in the same process may call it directly; remote components use ADFP.

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
- It is versioned independently of ADFP wire versions and runtime versions.
- Unsupported operations fail closed with a typed error.

## Native execution

Native execution is first-class. It covers native applications, platform APIs, hardware acceleration, background tasks and platform-specific integrations. A device is useful without Wanix.

## Browser agents

A browser endpoint is a presentation consumer. It may hold a browser identity and request scoped capabilities, but it is not a native agent and does not bypass platform or browser permissions.

## Agent failure

- Agent disconnect makes its capabilities unavailable.
- Leases associated with the agent are revoked or expired.
- Workspace definitions remain.
- The orchestrator reconciles when the agent returns.
- A stale agent identity or revoked device is rejected.

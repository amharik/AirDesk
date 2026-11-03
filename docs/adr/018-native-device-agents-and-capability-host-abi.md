# ADR-018: Native device agents and capability host ABI

- **Status:** Proposed — platform agent and capability ABI gates required
- **Date:** 2026-11-03
- **Deciders:** Engineering lead, security owner
- **Scope:** DeviceAgent contract, native adapters, capability descriptors, leases, host ABI, platform permissions
- **Supersedes:** None
- **Amends:** ADR-004, ADR-012, ADR-014
- **Related:** ADR-010, ADR-011, ADR-013, ADR-016, ADR-017

## Context

AirDesk targets heterogeneous devices with different platform permissions, process models, background limits and hardware access. Requiring Wanix on every device would make the fabric depend on one runtime and would not expose native platform functionality safely.

The blueprint makes native agents the integration boundary: devices contribute capabilities, and runtimes access those capabilities only through authorized adapters.

## Decision

### 1. Every participating platform has a native agent

A native agent exposes device functionality through a stable host interface. It is responsible for:

- device identity;
- capability advertisement;
- camera, microphone, filesystem, sensor and input permissions;
- native process and application integration;
- notifications;
- display integration;
- network and background constraints;
- health and lifecycle events.

Wanix does not replace the native agent.

### 2. DeviceAgent contract

```text
DeviceAgent
  identity()
  capabilities()
  requestCapability(capabilityId, request)
  releaseCapability(leaseId)
  subscribe(eventType, handler)
  health()
```

Each platform implements the contract with its own native APIs. The contract is logical; it does not require an RPC boundary between components in the same process.

### 3. Capability descriptors are sufficient for safe placement

```text
CapabilityDescriptor
  id, providerDeviceId
  type, version
  availability: available | busy | restricted | unavailable
  constraints
  permissions[]
  transport[]
  executionModel
  lifecycle
```

Initial capability namespaces include camera, audio input, pointer, keyboard, display output, file storage, database storage, native compute, WASI compute and location.

Advertisement is not permission. The orchestrator resolves a capability only after authorization and availability checks.

### 4. Access uses revocable leases

A capability lease contains:

- lease ID;
- device and capability IDs;
- workspace, application and requester IDs;
- granted operations;
- scope and constraints;
- issue and expiry times;
- revocation state;
- audit identifier.

Leases are time-bounded, scoped and revocable. Indefinite implicit access to device resources is prohibited.

### 5. Runtimes use a capability host ABI

- Wanix and other runtime providers access host functionality only through an explicit host adapter.
- The adapter enforces capability grants and platform permissions.
- The host adapter must not expose unrestricted filesystem, process or device access.
- The ABI is versioned independently of the runtime and ADFP wire versions.
- Unsupported host operations fail closed with a typed error.

### 6. Native execution remains first-class

- A device can be useful without running Wanix.
- Native applications, hardware acceleration and platform APIs are valid execution paths.
- A runtime provider may be unavailable on a platform without making the device unusable.
- Device agents must not assume that every workload runs in a browser or WASM sandbox.

### 7. Platform security remains authoritative

- iOS, Android, macOS, Windows and browser permission models remain in force.
- AirDesk grants do not override operating-system permission denial.
- A capability can be advertised but restricted by the platform.
- Revocation invalidates AirDesk leases but does not bypass platform revocation.

### 8. Device trust is not workspace membership

Pairing establishes device trust. It does not:

- grant workspace ownership;
- make the device a collaborator;
- grant all capabilities;
- authorize arbitrary input injection.

Those are separate authorization decisions.

## Consequences

### Positive

- Native functionality remains accessible.
- Wanix is optional on devices.
- Platform-specific restrictions remain enforceable.
- The fabric can support heterogeneous endpoints.
- Capability access is auditable and revocable.

### Negative

- Requires platform-specific agent implementations.
- Requires capability compatibility and versioning.
- Requires careful permission, lease and lifecycle management.
- A host ABI adds a security-sensitive boundary.

## Acceptance gates

- A device can expose and authorize a capability through a native agent.
- A capability request can be leased, used, expired and revoked.
- Wanix can access an approved host capability through the host ABI.
- Wanix cannot bypass the host ABI to obtain unrestricted host access.
- A device can run native workloads without Wanix installed.
- Platform permission denial is reported truthfully and cannot be overridden by an AirDesk grant.
- Pairing alone does not grant workspace ownership or optional capabilities.
- Device and capability schemas are versioned and fail closed on unsupported required versions.

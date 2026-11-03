# ADR-019: Application model and lifecycle

- **Status:** Proposed — manifest and lifecycle gates required
- **Date:** 2026-11-03
- **Deciders:** Product owner, engineering lead
- **Scope:** Application manifests, instances, desired/observed state, runtime requirements, lifecycle, remote applications
- **Supersedes:** None
- **Amends:** ADR-001, ADR-007
- **Related:** ADR-004, ADR-010, ADR-012, ADR-016, ADR-017, ADR-018

## Context

Applications currently exist as desktop shell entries and runtime-specific integrations. Their identity depends on whether they are built-in, Wanix-backed or terminal-backed. That prevents runtime replacement, placement and a consistent shell presentation.

The blueprint makes applications first-class workspace entities with provider-neutral manifests and lifecycle semantics.

## Decision

### 1. Application identity is provider-neutral

An application manifest describes:

```text
AirDeskApplicationManifest
  id, version, name
  entrypoint
  supportedRuntimes[]
  requiredCapabilities[]
  presentation
  permissions[]
  lifecycle
```

An application may be:

- native;
- web;
- Wanix/WASI;
- remote;
- built into AirDesk.

The manifest does not name a specific device or runtime instance.

### 2. Instances have desired and observed state

```text
ApplicationInstanceDefinition
  id, applicationId
  desiredState: running | stopped | suspended
  placement
  configuration
```

```text
ApplicationInstanceStatus
  instanceId
  observedState: starting | running | suspended | stopped | failed | unavailable
  runtimeProviderId
  runtimeInstanceId
  deviceId
  lastHeartbeat
  lastError
```

Desired state belongs to the workspace manifest. Observed state belongs to the orchestrator's runtime view. They must not be merged.

### 3. Lifecycle is standardized

```text
installed -> available -> starting -> running -> suspended -> stopped
                                      \-> failed
                                      \-> unavailable
```

- `unavailable` means no provider or device can currently realize the instance.
- `failed` means a provider attempted realization and reported an error.
- A failed or unavailable instance remains in the workspace with its definition.
- Recovery is a reconciliation outcome, not a manifest rewrite.

### 4. The shell uses a common application abstraction

The AirDesk Shell presents applications through a provider-neutral interface:

- application identity and icon;
- window and presentation metadata;
- lifecycle actions (open, focus, suspend, stop, restore);
- capability request prompts;
- error and unavailable states.

The shell must not depend on Wanix internals, runtime-specific DOM or a provider-specific process model.

### 5. Runtime requirements are declarative

- An application declares runtime requirements and required capabilities.
- The orchestrator selects a compatible provider and placement.
- An application that cannot be placed remains `unavailable`; it must not be silently run on an incompatible provider.
- Capability requirements are authorized separately from runtime availability.

### 6. Remote applications use the same model

Remote applications are provider adapters, not a separate workspace model.

- RDP RAIL, Xpra, SSH-backed terminals and similar integrations implement presentation/execution adapters.
- Remote application windows use the same window and lifecycle abstractions.
- Remote execution is explicit, not an implicit consequence of display connectivity.
- Remote application support is post-MVP.

### 7. Application data and resources are references

- Application instance data is referenced through workspace resource references.
- An application definition does not embed a device-local absolute path as its only identity.
- Resource access policy is separate from runtime placement.
- Uninstalling or stopping an application does not silently delete referenced resources.

## Consequences

### Positive

- Applications can move between compatible providers later.
- The shell is less runtime-specific.
- Remote applications can integrate without changing workspace identity.
- Desired and observed state have clear ownership.
- Runtime failure can be reported without losing application definitions.

### Negative

- Requires application packaging and compatibility rules.
- Requires a stable lifecycle and error contract.
- Adds manifest and migration work.
- Some current built-in applications need adapter shims before they fit the model.

## Acceptance gates

- An application manifest validates without naming a device or runtime instance.
- The orchestrator can place an instance on a compatible provider.
- Observed state transitions do not rewrite desired state.
- A provider failure leaves the application definition intact and reports `failed` or `unavailable`.
- The shell uses the provider-neutral application/window abstraction.
- Required capabilities are authorized separately from runtime availability.
- An incompatible provider fails closed rather than silently substituting.
- Remote application adapters do not change the workspace identity model.

## Out of scope

- An app store or distribution marketplace.
- Arbitrary live process migration.
- Cross-device application data synchronization.
- Multi-user application permissions.
- Third-party application sandbox certification.

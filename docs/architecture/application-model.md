# Application model

Applications are first-class workspace entities. They are independent of the desktop shell and the runtime provider.

## Manifest

```text
AirDeskApplicationManifest
  schemaVersion
  id, version, name
  entrypoint
  runtimeTargets[]
  requiredCapabilities[]
  presentation
  permissions[]
  quotas
  lifecycle
```

`quotas` bounds workers, memory, CPU time, open handles, stream buffers and persisted bytes per application instance.

```text
RuntimeTarget
  provider: native | wanix | browser | remote
  world: wasi-cli@0.2 | wasi-http@0.2 | wasi-filesystem@0.2 | wasi-sockets@0.2 | ...
```

An application may be native, web, Wanix/WASI, remote or built into AirDesk. WASI applications pin a Component Model world and version; Preview 1 and WASIX are explicit compatibility/vendor targets, not aliases for WASI 0.2.

## Instances

Desired state belongs to the workspace manifest:

```text
ApplicationInstanceDefinition
  id, applicationId
  desiredState: running | stopped | suspended
  placement
  configuration
```

Observed state belongs to orchestration:

```text
ApplicationInstanceStatus
  instanceId
  observedState: starting | running | suspended | stopped | failed | unavailable
  runtimeProviderId, runtimeInstanceId, deviceId
  lastHeartbeat, lastError
```

## Lifecycle

```text
installed -> available -> starting -> running -> suspended -> stopped
                                      \-> failed
                                      \-> unavailable
```

- `unavailable` means no provider or device can realize the instance.
- `failed` means a provider attempted realization and reported an error.
- Failed and unavailable instances remain in the workspace with their definitions.

Sandboxed applications additionally use an explicit sandbox lifecycle:

```text
RESOLVED -> MOUNTING_CAPABILITIES -> ACTIVE_FOREGROUND <-> ACTIVE_BACKGROUND
         -> SUSPENDED_CHECKPOINTED -> TERMINATED
```

- A failure while mounting capabilities terminates the instance with a typed error and no partial mount.
- `TERMINATED` revokes all capability handles and leases before releasing resources and is idempotent.
- Quota exhaustion moves the instance to `failed`; it never silently degrades the workspace.

## Shell boundary

The shell presents applications through a provider-neutral interface:

- identity and icon;
- window and presentation metadata;
- open, focus, suspend, stop and restore actions;
- capability request prompts;
- error and unavailable states.

The shell must not depend on Wanix internals or runtime-specific DOM.

## Remote applications

Remote applications are provider and presentation adapters:

- RDP RAIL;
- Xpra;
- SSH-backed terminals;
- future remote protocols.

They use the same application and window abstractions. Remote support is post-MVP and requires explicit placement. Remote-application protocols are advertised through AD-CAP, not hard-coded in the workspace. Prefer Xpra-style persistent sessions and report whether a remote application survived disconnect.

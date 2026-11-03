# Application model

Applications are first-class workspace entities. They are independent of the desktop shell and the runtime provider.

## Manifest

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

An application may be native, web, Wanix/WASI, remote or built into AirDesk.

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

They use the same application and window abstractions. Remote support is post-MVP and requires explicit placement.

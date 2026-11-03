# AD-RUNTIME

AD-RUNTIME is the ADFP module for runtime provider lifecycle and execution status.

## Scope

- Runtime provider advertisement.
- Runtime instance creation, start, suspend, stop and destroy.
- Execution requests.
- Observed runtime status and errors.
- Runtime capability negotiation.
- Remote namespace role (runtime, resource or both) and 9P binding.

It does not define workspace persistence, application identity, placement policy or capability authorization. Those belong to AD-WS, AD-APP, AD-CAP and the orchestrator.

## Provider descriptor

```text
RuntimeProviderDescriptor
  providerId, deviceId
  kind: native | wanix | browser | remote
  version
  capabilities[]
  supportedArchitectures[]
  wasiWorlds[]
  taskDrivers[]
  namespaceRoles[]
  resourceLimits
```

## Messages

| Type | Direction | Purpose |
| --- | --- | --- |
| `runtime.provider.advertise` | Provider → orchestrator | Provider availability and capabilities |
| `runtime.instance.create` | Orchestrator → provider | Create an instance from an application request |
| `runtime.instance.start` | Orchestrator → provider | Start an instance |
| `runtime.instance.suspend` | Orchestrator → provider | Suspend an instance |
| `runtime.instance.stop` | Orchestrator → provider | Stop an instance |
| `runtime.instance.destroy` | Orchestrator → provider | Release instance resources |
| `runtime.instance.status` | Provider → orchestrator | Observed state and heartbeat |
| `runtime.exec.request` | Orchestrator/application → provider | Execute a command or operation |
| `runtime.exec.result` | Provider → requester | Execution result |
| `runtime.error` | Provider → orchestrator | Typed failure |

## Status

```text
observedState: starting | running | suspended | stopped | failed | unavailable
```

Status must distinguish provider failure from unavailability and from desired-state changes. A remote 9P namespace must report whether it is mounted, degraded or gone, and whether it is a runtime, resource or both.

## Placement

The orchestrator chooses a provider. AD-RUNTIME reports compatibility and observed capacity; it does not choose placement.

## Security

- Requests are authenticated and authorized.
- Runtime instances receive only the capability leases required for their work.
- Provider credentials and workspace secrets must not be sent in clear text.
- Unsupported operations fail closed.

## Transport

AD-RUNTIME is semantic. It may run over local IPC, WebSocket/TLS, WebRTC data channels, QUIC or a future transport without changing meaning. Large execution output belongs on a data-plane stream.

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

## Stream framing and flow control

AD-RUNTIME instance streams run on ADFP Channels 2..N as reliable, bidirectional streams multiplexed per instance and per channel kind (`stdin`, `stdout`, `stderr`, `signal`, `resize`).

| Field | Purpose |
| --- | --- |
| `stream_id` | Multiplexed stream identity within the instance |
| `channel` | `stdin`, `stdout`, `stderr`, `signal`, `resize` |
| `seq` | Monotonic per-stream byte or message sequence |
| `credit` | Bytes the receiver is willing to accept |

- Flow control is a 256 KiB in-flight credit window per stream, with a 128 KiB resume threshold (hysteresis).
- A producer pauses when the window is exhausted; execution output is never silently dropped.
- A slow build in Terminal A must not block interactive input in Terminal B or the input plane.
- Control messages carry lifecycle, status and errors; bulk output stays on the data plane.
- Stream teardown is explicit and idempotent; a disconnected consumer cancels or suspends the instance per policy.

## Placement

The orchestrator chooses a provider. AD-RUNTIME reports compatibility and observed capacity; it does not choose placement.

## Security

- Requests are authenticated and authorized.
- Runtime instances receive only the capability leases required for their work.
- Provider credentials and workspace secrets must not be sent in clear text.
- Unsupported operations fail closed.

## Transport

AD-RUNTIME is semantic. It may run over local IPC, WebSocket/TLS, WebRTC data channels, QUIC or a future transport without changing meaning. Large execution output belongs on a data-plane stream.

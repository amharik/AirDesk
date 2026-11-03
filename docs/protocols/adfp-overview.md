# ADFP overview

The AirDesk Fabric Protocol (ADFP) is the semantic protocol between AirDesk components. It is transport-neutral and versioned.

ADFP carries intent and observed results. It does not make the sender the workspace authority.

## Envelope

```json
{
  "protocol": "adfp",
  "version": "0.1",
  "messageId": "uuid",
  "correlationId": "uuid-or-null",
  "timestamp": "RFC3339",
  "sender": { "deviceId": "...", "role": "agent" },
  "workspaceId": "...",
  "module": "AD-RUNTIME",
  "type": "runtime.start",
  "payload": {}
}
```

Required behavior:

- Unknown major versions are rejected with a typed error.
- Unknown message types are ignored or rejected according to the module contract.
- Messages are authenticated and bound to device or session identity.
- Large payloads do not go through the control plane.
- Replay protection applies to mutable and security-sensitive operations.

## Modules

| Module | Status | Purpose |
| --- | --- | --- |
| AD-WS | Active | Workspace desired state, placement and observed status |
| AD-DEV | Active | Device identity, discovery, pairing and health |
| AD-CAP | Active | Capability advertisement, leases, revocation and remote-application protocol descriptors |
| AD-RUNTIME | Active MVP | Runtime provider lifecycle, execution status and remote namespace role |
| AD-RESOURCE | Active MVP | File and resource access |
| AD-INPUT | Active MVP | Keyboard, pointer, touch and controller events |
| AD-DISPLAY | Active MVP | Display capability, viewport and presentation status |
| AD-APP | Early | Application lifecycle and launch requests |
| AD-WINDOW | Early | Window and layout presentation messages |
| AD-SYNC | Later | Encrypted workspace synchronization |
| AD-MEDIA | Later | Audio, video and media streams |
| AD-AI | Later | Intent and agent operations |
| AD-GROUP | Later | Shared workspace membership and collaboration |

## Boundary rules

- AD-RUNTIME does not define workspace persistence.
- AD-RUNTIME may describe a remote Wanix namespace imported over 9P, but the mount is not workspace authority.
- AD-RESOURCE does not grant unrestricted filesystem access.
- AD-INPUT carries controller events; it does not decide workspace ownership.
- AD-DISPLAY presents state; it does not write canonical workspace state.
- AD-WS expresses desired and observed state without transferring authority to the coordinator or provider.

## Related documents

- `ad-runtime.md`
- `ad-resource.md`
- `protocol-versioning.md`
- `transport-mapping.md`

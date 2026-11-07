# ADFP overview

The AirDesk Fabric Protocol (ADFP) is the semantic protocol between AirDesk components. It is transport-neutral and versioned.

ADFP carries intent and observed results. It does not make the sender the workspace authority.

## Wire schema

`protocol/airdesk.fbs` is the canonical FlatBuffers schema; generated Swift, TypeScript, Rust and Kotlin bindings are authoritative for field IDs and offsets. The JSON used elsewhere in this document is an illustrative semantic view, not a second wire format.

The root `Envelope` carries file identifier `ADEN`:

| Field | ID | Type | Notes |
| --- | --- | --- | --- |
| `version` | 0 | `uint` | Default `1`; unknown major versions are rejected |
| `payload` | 2 | `MessagePayload` | Baseline v1 union: `InputEvent`, `ControlMessage` |
| `header` | 3 | `ControlHeader` | Optional control-plane metadata; all fields optional |
| `fabric_payload` | 5 | `FabricPayload` | Additive union for identity, capability, display, sync and group primitives |

`ControlHeader` carries optional `message_id`, `sender_device_id`, `sender_role`, `correlation_id`, `idempotency_key`, `expires_at` (Unix epoch milliseconds) and `cancellation_id`.

`FabricPayload` is an additive union. Existing v1 `MessagePayload` members are unchanged, so baseline v1 envelopes and fixtures remain conformant:

| Payload | Purpose |
| --- | --- |
| `DeviceIdentity` | Stable device ID, opaque public key, nonce/expiry, channel-binding hint and capability URI hints |
| `PairingOffer` / `PairingResponse` | Offer/response nonce, expiry, channel binding and capability hints |
| `CapabilityDescriptor` | `cap_uri`, provider device, four-value availability, explicit authorization and descriptive constraints |
| `CapabilityLease` | Lease scope, timestamps, revocation, operations and audit ID |
| `DisplaySession` | Workspace/display identity, viewport, profile and generation |
| `SyncRecord` | Workspace/record/device/user identity, sequence, merge class and opaque payload hash |
| `GroupMember` | Workspace/device/user identity, collaboration role and sequence |

The additive enums are `Availability`, `Authorization`, `MergeClass`, `ChannelBindingKind`, `DeviceKind` and `SenderRole`.

Required behavior:

- Unknown major versions are rejected with a typed error.
- Unknown message types are ignored or rejected according to the module contract.
- Messages are authenticated and bound to device or session identity.
- Large payloads do not go through the control plane.
- Replay protection applies to mutable and security-sensitive operations.

## Crypto and authority boundary

The FlatBuffers schema is structural. It declares identity, pairing, binding and lease fields but does not implement or assert cryptography:

- `public_key` and channel-binding values are opaque encodings in the schema.
- The browser has the AD-PAIR-1 canonical transcript, transcript signatures, binding enforcement, SAS and HKDF key schedule, plus an RFC 9383 P-256 SPAKE2+ primitive validated against the RFC vector; interactive pairing, QR/PIN exchange and channel-binding acquisition are not implemented.
- Browser code implements compact `COSE_Sign1` grant issuance and verification with bounded delegation, scoped leases, `cnf` proof-of-possession, signed revocation snapshots and provider-side request authorization; native issuance, revocation distribution and native invocation enforcement remain pending.
- `SyncRecord.payload_hash` is an opaque digest; no synchronization transport is implied.
- A capability advertisement, pairing offer or lease payload never grants workspace ownership.

## Modules

| Module | Status | Purpose |
| --- | --- | --- |
| AD-WS | Active | Workspace desired state, placement and observed status |
| AD-DEV | Early | Device identity, discovery, pairing and health; identity, local registry, the AD-PAIR-1 transcript/key schedule, interactive SPAKE2+ pairing and canonical DNS-SD advertisement records exist; the runtime discovery adapter and real channel binding remain pending |
| AD-CAP | Early | Capability advertisement, leases, revocation and remote-application protocol descriptors; schema, Android advertisement, the iOS local capability catalog and browser `COSE_Sign1` grants/leases/proof-of-possession/revocation snapshots/provider authorization exist, while revocation distribution, native invocation enforcement and remote invocation remain pending |
| AD-RUNTIME | Active MVP | Runtime provider lifecycle, execution status and remote namespace role |
| AD-RESOURCE | Active MVP | File and resource access |
| AD-INPUT | Active MVP | Keyboard, pointer, touch and controller events |
| AD-DISPLAY | Active MVP | Display capability, viewport and presentation status |
| AD-APP | Early | Application lifecycle and launch requests |
| AD-WINDOW | Early | Window and layout presentation messages |
| AD-SYNC | Early | Encrypted workspace synchronization; merge/envelope foundations exist in the browser and iOS, with native envelopes carried over a reliable Iroh `.sync` channel; session/offline flushing and workspace-store integration remain pending |
| AD-MEDIA | Later | Audio, video and media streams |
| AD-AI | Later | Intent and agent operations |
| AD-GROUP | Early | Shared workspace membership and collaboration; roles/audit foundations only |

## Boundary rules

- AD-RUNTIME does not define workspace persistence.
- AD-RUNTIME may describe a remote Wanix namespace imported over 9P, but the mount is not workspace authority.
- AD-RESOURCE does not grant unrestricted filesystem access.
- AD-INPUT carries controller events; it does not decide workspace ownership.
- AD-DISPLAY presents state; it does not write canonical workspace state.
- AD-WS expresses desired and observed state without transferring authority to the coordinator or provider.

## Generated bindings

`./protocol/generate.sh` emits Swift, TypeScript, Rust and Kotlin bindings. `./protocol/check.sh` verifies baseline conformance and generated Kotlin drift; `protocol/patch-generated-ts.sh` preserves existing TypeScript `Envelope.createEnvelope` callers. Kotlin bindings are consumed by the Android app under `protocol/generated/kotlin`.

## Related documents

- [ad-runtime.md](ad-runtime.md)
- [ad-resource.md](ad-resource.md)
- [protocol-versioning.md](protocol-versioning.md)
- [transport-mapping.md](transport-mapping.md)
- [ad-pair-1.md](ad-pair-1.md)
- [browser-endpoint.md](browser-endpoint.md)

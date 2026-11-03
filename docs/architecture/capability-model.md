# Capability model

AirDesk exposes device functionality as scoped capabilities. A device does not grant wholesale access to its camera, files, compute or input.

## Descriptor

```text
CapabilityDescriptor
  cap_uri, providerDeviceId
  type, version
  availability: available | busy | restricted | unavailable
  constraints
  permissions[]
  transport[]
  executionModel
  lifecycle
```

Advertisement is not permission. Availability and authorization are separate axes.

## Authorization

Every capability operation is checked against:

- device identity;
- workspace identity;
- requesting application and instance;
- capability scope;
- user consent;
- lease validity;
- platform permission;
- revocation state.

## Leases

A capability lease contains:

- lease ID;
- device and `cap_uri`;
- workspace and application IDs;
- requester device and session;
- granted operations and resource scope;
- issue and expiry;
- revocation state;
- constraints;
- audit identifier.

A lease cannot outlive its grant or workspace authorization. It is scoped to one application instance unless the capability contract permits sharing.

## Grant tokens

Grants and delegated chains are compact `COSE_Sign1` tokens signed with Ed25519. Claims include `iss`, `sub`, `aud`, `jti`, `cap_uri`, `op`, `nbf`, `exp`, `epoch_id` (session `generation`), optional `cnf` and a parent hash.

- Root grants are issued only by the provider device's authenticated user or the workspace owner key; the coordinator and requester cannot mint them.
- A chain is at most 3 hops: provider-approved root → workspace orchestrator → runtime task.
- Each hop may only attenuate scope, operations and expiry.
- Effective validity is the latest `nbf` to the earliest `exp` across the chain.
- Chain length and token size are bounded before parsing.
- A `cnf` claim requires proof of possession on every invocation.
- Compact binary tokens are used instead of nested-JWT UCAN because UCAN adds DID resolution and per-hop envelope overhead at runtime.

## Revocation

- Revocation records are signed and sequence-numbered.
- The coordinator may distribute revocation records but cannot mint grants or leases.
- A provider that cannot obtain a sufficiently current revocation record fails closed for high-impact capabilities.
- Offline providers may use an explicit bounded-staleness window.
- Revocation cancels new invocations and in-flight work unless a safe completion path is declared.

## Examples

- `airdesk://fs/documents/read`
- `airdesk://fs/documents/write`
- `airdesk://media/camera/capture`
- `airdesk://audio/input`
- `airdesk://input/pointer`
- `airdesk://input/keyboard`
- `airdesk://display/output`
- `airdesk://compute/wasi/execute`
- `airdesk://location/read`

Do not grant `filesystem.access` or other device-wide authorities.

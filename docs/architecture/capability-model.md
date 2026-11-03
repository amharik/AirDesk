# Capability model

AirDesk exposes device functionality as scoped capabilities. A device does not grant wholesale access to its camera, files, compute or input.

## Descriptor

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
- device and capability IDs;
- workspace and application IDs;
- requester device and session;
- granted operations and resource scope;
- issue and expiry;
- revocation state;
- constraints;
- audit identifier.

A lease cannot outlive its grant or workspace authorization. It is scoped to one application instance unless the capability contract permits sharing.

## Revocation

- Revocation records are signed and sequence-numbered.
- The coordinator may distribute revocation records but cannot mint grants or leases.
- A provider that cannot obtain a sufficiently current revocation record fails closed for high-impact capabilities.
- Offline providers may use an explicit bounded-staleness window.
- Revocation cancels new invocations and in-flight work unless a safe completion path is declared.

## Examples

- `filesystem.documents.read`
- `filesystem.documents.write`
- `media.camera.capture`
- `audio.input`
- `input.pointer`
- `input.keyboard`
- `display.output`
- `compute.wasi.execute`
- `location.read`

Do not grant `filesystem.access` or other device-wide authorities.

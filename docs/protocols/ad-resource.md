# AD-RESOURCE

AD-RESOURCE is the ADFP module for scoped resource access between workspace components.

## Scope

- File and document access.
- Resource metadata and availability.
- Read, write and watch operations where authorized.
- Streaming resources.
- Resource references and provider binding.

It does not grant device-wide filesystem access, bypass platform permissions or define workspace persistence.

## Resource reference

```text
ResourceReference
  id
  kind: file | document | database | application-data | runtime-volume
  providerId
  resourceId
  accessPolicy
  persistence
```

The reference is stable enough for the workspace to retain it, but it does not imply universal reachability. Availability is resolved by the orchestrator or device agent for the current placement.

## Operations

| Operation | Purpose |
| --- | --- |
| `resource.stat` | Metadata and availability |
| `resource.open` | Open a scoped handle |
| `resource.read` | Read content |
| `resource.write` | Write content |
| `resource.watch` | Subscribe to changes |
| `resource.close` | Release a handle |
| `resource.error` | Typed failure |

## Authorization

Every operation requires:

- a valid capability lease;
- workspace and application context;
- the requested operation inside the lease scope;
- platform permission.

A resource reference is not an authorization token.

## Streaming

Content and large transfers use a data-plane stream. Control messages carry metadata, handles and errors only. Streams must be authenticated and tied to the requesting workspace, application and lease.

## Failure behavior

- Missing resource: typed `not_found`.
- Denied access: typed `unauthorized`.
- Revoked lease: `revoked`; stop new operations.
- Provider unavailable: `unavailable`; retain the reference for later recovery.
- Conflicting update: report a typed conflict; do not silently overwrite.

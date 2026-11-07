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

## ADFP channel mapping

AD-RESOURCE runs on ADFP Channel M..K as reliable, bidirectional QUIC/WebTransport streams (or the WebSocket fallback), separate from the input hot path and from interactive terminal streams. A large file read or write must not block pointer input or terminal output.

Each mount is a Plan 9-inspired file service in the workspace namespace (`/#cap` or `/workspace`). Messages are encoded inside the FlatBuffers `ResourceRpc` table and its `ResourceRpcPayload` union.

## ADFP resource RPC surface (not 9P2000)

These names and numbers are **ADFP-local op codes**, not 9P2000 message types. ADFP does not tunnel 9P2000 frames: there is no `Tversion`/`Rversion`, no 2-byte 9P tag field, and no 9P `msize` negotiation on this path. Calling them "9P tags" is incorrect; the implementation must not expect a 9P2000 peer to interoperate. If real 9P interop is needed later, it is a separate adapter that tunnels encoded 9P frames inside `ResourceRpc` and is qualified as such.

| RPC | ADFP op code | Fields | Semantics |
| --- | --- | --- | --- |
| `Attach` / `AttachResult` | 100 / 101 | `fid:u32`, `afid:u32`, `uname:string`, `aname:string`, `cose_token:[ubyte]` | Validate the ADR-012 `COSE_Sign1` token against `aname` (`opfs`, `tarfs`, `tmpfs`, `hostfs`) and bind the root handle |
| `Walk` / `WalkResult` | 102 / 103 | `fid:u32`, `new_fid:u32`, `wnames:[string] -> wqids:[Qid]` | Traverse path segments relative to `fid`; reject `..` escapes outside the capability root; return `Qid` tuples |
| `Open` / `OpenResult` | 104 / 105 | `fid:u32`, `mode:BindMode -> qid:Qid`, `iounit:u32` | Open under Wanix bind mode (`READ_ONLY`, `READ_WRITE`, `EXEC`, `APPEND`); default `iounit` is 65536 bytes |
| `Read` / `ReadResult` | 106 / 107 | `fid:u32`, `offset:u64`, `count:u32 -> data:[ubyte]` | Read up to `count` bytes from the underlying Wanix or native descriptor |
| `Write` / `WriteResult` | 108 / 109 | `fid:u32`, `offset:u64`, `data:[ubyte] -> count:u32` | Write at `offset`; rejected immediately for a read-only attenuated token |
| `Clunk` / `ClunkResult` | 110 / 111 | `fid:u32 -> status:ubyte` | Release `fid` deterministically on close, task exit or lease revocation (ADR-015) |

`Qid` carries the 9P field order as `type:u8`, `version:u32`, `path:u64`; FlatBuffers struct alignment pads the inline representation, so this is a typed ADFP layout, not a 9P2000 wire frame. `Stat`/`StatResult` and `Wstat`/`WstatResult` (112–115) expose and update bounded metadata; they never expose host paths outside the mount root.

## Streaming

Content and large transfers use a data-plane stream. Control messages carry metadata, handles and errors only. Streams must be authenticated and tied to the requesting workspace, application and lease.

Per-stream byte-credit flow control bounds in-flight data; a slow consumer pauses its stream without stalling other mounts or the input plane.

## Failure behavior

- Missing resource: typed `not_found`.
- Denied access: typed `unauthorized`.
- Revoked lease: `revoked`; stop new operations.
- Provider unavailable: `unavailable`; retain the reference for later recovery.
- Conflicting update: report a typed conflict; do not silently overwrite.

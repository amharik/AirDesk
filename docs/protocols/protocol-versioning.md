# Protocol versioning

AirDesk versions protocols, schemas and capability contracts independently.

## Version surfaces

| Surface | Example | Compatibility rule |
| --- | --- | --- |
| ADFP envelope | `adfp 1.0` | Major version negotiation required |
| Module | `AD-RUNTIME 1.0` | Module-specific version |
| Workspace schema | `workspace 1` | Store migration required |
| Runtime provider | `wanix-provider 1` | Provider contract version |
| Capability host ABI | `host-abi 1` | Native adapter version |
| Capability descriptor | `camera.capture@1` | Capability-specific contract |
| Application manifest | `app-manifest 1` | Install and launch validation |
| WASI target | `wasi-cli@0.2` | World and version checked at placement |
| Transport binding | `webtransport-http3` | Transport protocol negotiated separately from ADFP |

Do not use one version number for all surfaces.

## Compatibility

- Major version changes may break interoperability.
- Minor versions add backward-compatible messages or optional fields.
- Patch versions clarify behavior without changing the contract.
- Unknown required fields and unknown major versions fail closed.
- Unknown optional fields are preserved or ignored according to the schema.

## Negotiation

Peers advertise supported ADFP major versions, module versions, runtime contracts, capability versions and transport bindings. The highest mutually supported compatible version is selected. There is no silent downgrade.

ADFP semantic compatibility and transport compatibility are negotiated separately. A peer that supports WebTransport is not automatically compatible with the endpoint's HTTP/3 deployment, and a WASI 0.2 peer is not a WASI 0.3 peer.

## FlatBuffers evolution rules

`protocol/airdesk.fbs` declares `file_identifier "ADEN"`. Every FlatBuffers payload is validated with `EnvelopeBufferHasIdentifier()` before field access.

- Every field in `Envelope`, `InputEvent` and `ControlMessage` carries a contiguous `(id: n)` attribute; a union member consumes two consecutive IDs.
- Fields and union variants are appended or explicitly pinned; they are never removed or reordered.
- Scalar defaults never change after release; obsolete fields are marked `(deprecated)`.
- A committed `protocol/baseline/airdesk_vN.fbs` freezes each released schema.
- CI runs `flatc --conform protocol/baseline/airdesk_vN.fbs protocol/airdesk.fbs` and fails on any breaking change.
- Regenerated Swift, Rust and TypeScript bindings must show zero diff in the same change.

## Schema migration

- Workspace documents carry `schemaVersion`.
- Migration is explicit, reversible where possible and backed up before writing.
- A future schema is rejected rather than opened with lossy defaults.
- Downgrade requires an explicit export or migration path.

## Deprecation

- Deprecated fields remain readable for a documented window.
- Removal requires a major version or module version change.
- Security fixes may require immediate rejection of a vulnerable version.
- Compatibility claims must be tested, not inferred.

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

Do not use one version number for all surfaces.

## Compatibility

- Major version changes may break interoperability.
- Minor versions add backward-compatible messages or optional fields.
- Patch versions clarify behavior without changing the contract.
- Unknown required fields and unknown major versions fail closed.
- Unknown optional fields are preserved or ignored according to the schema.

## Negotiation

Peers advertise supported ADFP major versions, module versions, runtime contracts and capability versions. The highest mutually supported compatible version is selected. There is no silent downgrade.

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

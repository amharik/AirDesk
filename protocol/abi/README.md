# AirDesk capability host ABI

The capability host ABI is the versioned, lease-checked boundary between a
runtime (Wanix, the native Rust/Swift agent or a browser adapter) and a native
device agent. The normative contract is the WIT package
`airdesk:host-abi@0.2.0` in `wit/airdesk-host-abi.wit`.

The package relies on the WASI 0.2 Component Model baseline and imports
`wasi:io/streams@0.2.0`. Those WIT files are vendored under `wit/deps/io` so the
package can be resolved without pulling an unpinned WASI checkout. Native
providers that execute `wasi-cli@0.2` worlds may import `wasi:cli/run@0.2.0`
alongside this package; that is a runtime/application world concern, not part of
the capability surface.

## Interfaces

| Interface | Bound protocol | Capability URI | Surface |
| --- | --- | --- | --- |
| `vfs-service` | AD-RESOURCE | `airdesk://fs/<mount_id>/<mode>` | `mount-capability`, confined `node` stat/open/read/write/readdir/close |
| `pty-service` | AD-RUNTIME | `airdesk://pty/<profile_id>` | `spawn`, lease-bound `pty-session` stdin/stdout/resize/terminate/wait/credits |
| `display-sink` | AD-DISPLAY / ADR-014 | `airdesk://display/output` | `register-sink`, presentation-state read/update/close |

`display-sink` deliberately has **no frame submission operation**. Frames remain
owned by the display session (ADR-001/ADR-005/ADR-014); adding `submit-frame`,
`submit-surface` or a pixel payload here would create a second, unaudited
presentation path that bypasses `OriginPolicy`. Input subscription also belongs
to the display-session protocol rather than this native capability host.

## Lease enforcement

Every function takes a `capability-grant` containing the `COSE_Sign1` capability
token and the claimed `lease-context`. A host implementation must:

- validate the token signature, issuer, provider, workspace, application,
  requester, operation set, expiry and `lease-epoch` on every call;
- compare the claims with the authenticated token instead of trusting the
  caller-supplied context;
- revalidate the same grant on each operation of a returned stream handle and
  close the handle when the lease expires or is revoked;
- check the platform permission separately; an AirDesk grant cannot override an
  operating-system denial;
- return a typed `abi-error` without host paths, tokens, credentials or other
  secrets.

Unsupported operations and unsupported ABI/world versions fail closed. A device
or runtime is not assumed to be equivalent because both consume this WIT; each
runtime records a qualification result for every interface it claims.

## Path and stream rules

- `vfs-service` paths are relative to the mounted node. Implementations reject
  `..` escapes and must not follow symlinks unless `open-flags.no-follow` is
  absent and the lease grants that operation.
- `open-at` never widens beyond the mount's canonicalized subtree.
- `read-stream` and `write-stream` handles are bound to the originating grant.
- PTY streams use the fixed `pty-credit-window` contract: 262144 bytes maximum
  in flight, 131072 bytes resume threshold and 65536-byte maximum chunk. The
  host pauses a producer at the window limit and resumes at the threshold; it
  never silently drops output.
- `pty-service` bridges the native macOS/iOS PTY path or `SSHPTYSession`; it does
  not invent a second terminal protocol.

## Versioning

- 0.2 is the current WASI 0.2 baseline. It has no component-model `stream<T>` or
  `future<T>` types.
- 0.3 is a separate package and world in `airdesk-host-abi-0_3.wit`. It uses
  `async func`, `stream<T>` and `future<T>` and does not import `wasi:io`.
  A mixed 0.2/0.3 world, a 0.3 world that imports `wasi:io`, or a silent 0.3 to
  0.2 shim is a qualification failure.
- The ABI version is independent of ADFP wire versions, runtime versions and
  namespace layout.

## Check

```sh
./protocol/abi/check.sh
```

The check requires `wasm-tools` 1.263.0 (or set `WASM_TOOLS=/path/to/wasm-tools`).
It validates the WIT packages with `wasm-tools component wit`, verifies the
required interfaces and functions, checks the fixed PTY credit values, enforces
the no-frame-submission rule, verifies the 0.2/0.3 separation and compares the
frozen fixture at `protocol/fixtures/host-abi/wit-v1.json`.

`./protocol/abi/conformance/check.sh` runs the static gate and validates the
runtime conformance manifest. No runtime is currently marked qualified; a
passed result requires an evidence file and an explicit entry in
`qualifiedRuntimes`.

`protocol/fixtures/host-abi/wit-v1.json` is the P0-06 frozen contract fixture;
it supersedes the earlier 0.1.0 draft reference. Changes to the fixture or the
WIT require review from every consumer owner.

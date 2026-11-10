# AirDesk host ABI conformance

This directory tracks conformance for the capability host ABI. It separates
the static WIT gate from runtime qualification so a WIT file can never be
mistaken for proof that Wanix, Rust or Swift implements it.

## Layers

1. **Static ABI gate** — `protocol/abi/check.sh` resolves the 0.2 package,
   resolves the separate 0.3 package, checks required interfaces and typed
   errors, rejects mixed 0.2/0.3 worlds and rejects any display frame path.
2. **Runtime qualification** — each runtime must execute the interfaces it
   claims and record evidence in `manifest.json`. Cross-runtime equivalence is
   demonstrated per interface, not assumed from one WIT definition.

`manifest.json` currently records every runtime as `not-run` and
`qualifiedRuntimes` is empty. The check fails if a runtime is marked passed or
failed without a corresponding evidence record, so this repository does not
claim any runtime conformance yet.

## Run

```sh
./protocol/abi/conformance/check.sh
```

The harness runs the static ABI gate first. It requires `wasm-tools` 1.263.0
(or `WASM_TOOLS=/path/to/wasm-tools`) because resolving the WIT packages is part
of the gate.

# ADR-004: Runtime providers and execution baseline

- **Status:** Proposed — packaging, provider and performance gates required
- **Date:** 2026-10-29
- **Updated:** 2026-11-03 — Wanix re-scoped as preferred provider; native and browser providers first-class
- **Updated:** 2026-11-03 — research update: Wanix task drivers and 9P namespaces, WASI 0.2 worlds, WASIX demoted, threading profiles
- **Scope:** Runtime provider model, Wanix packaging, WASI targets, task drivers, 9P namespaces, threading profiles, mobile/web FFI, runtime assets, Puter disposition
- **Amends:** ADR-001 runtime implementation choice only; workspace, display and protocol authority comes from ADR-016/017
- **Supersedes:** None
- **Related:** ADR-001, ADR-003, ADR-006, ADR-007, ADR-009, ADR-014, ADR-017, ADR-018, ADR-019

## Decision

AirDesk uses a provider-neutral runtime model. Wanix is the preferred portable runtime provider, not the only runtime.

- Native platform execution is a first-class provider.
- Browser execution is a first-class provider for web applications and browser presentation.
- Wanix executes portable WASI workloads and can host multiple task drivers in its unified namespace where the platform supports them.
- Wanix may import or export namespaces over 9P/WebSocket. A remote namespace is an execution/resource mechanism, not workspace authority.
- Host functionality reaches Wanix through the capability host ABI, layered on Wanix's file-service boundary rather than an unrestricted host bridge.
- No device is required to install or run Wanix.
- A runtime provider binds to a workspace; it does not own workspace identity, persistence or orchestration.

The provider contract, registry and placement policy are defined by ADR-017.

### Wanix execution baseline

- Wanix executes inside the web runtime on iOS, and later inside Android WebView and a Cast receiver. It does not run as an in-process native Go runtime in the baseline.
- Wanix is a Plan 9-inspired namespace and task system, not only a WASI wrapper. Its task drivers include Go/TinyGo (`gojs`), WASI Wasm, JavaScript workers and v86 x86 Linux. Only qualified drivers ship on a given platform.
- WASI 0.2 Component Model worlds are AirDesk's portable application baseline: `wasi-cli@0.2`, `wasi-http@0.2`, `wasi-filesystem@0.2` and `wasi-sockets@0.2`. Preview 1 modules may be adapted where a toolchain or task driver requires them.
- Wanix's documented `wasi` task driver targets `wasip1`. WASI 0.2 support is a qualification gate for the selected driver/toolchain, not an assumed property of Wanix.
- Application manifests reference a world and version, not just "WASI". A runtime provider must reject unsupported worlds with a typed capability error.
- WASI 0.3 is stable as of June 2026 and supported by Wasmtime 46+ and jco, but it is not the baseline until Wanix's execution path and the selected toolchain pass qualification. Do not claim 0.3 support from manifest metadata alone.
- WASIX is a Wasmer-specific extension, not the standards baseline. Support it only for a named workload that cannot be built against WASI 0.2/0.3 and only after dependency admission.
- `wazero`, WAMR, Wasmtime and v86 are implementation choices, not architecture. Adopt one only for a named workload and a measured gap in the selected Wanix task driver.
- Threaded WebAssembly requires `SharedArrayBuffer` and cross-origin isolation. The default browser profile is single-threaded; threaded execution is an opt-in profile with a single-threaded fallback.
- Remote namespace import over 9P/WebSocket is a candidate transport for Release 4. It must not bypass capability leases or workspace authority.
- Rust shared cores use UniFFI for Swift/Kotlin bindings. Gomobile is limited to Go/Wanix boundaries where no Rust boundary is appropriate.
- All runtime and terminal assets are bundled locally. No production path depends on a runtime CDN.
- Puter is removed entirely. It is not a production runtime, fallback, reference implementation, demo fixture or bundled asset.

ADRs 001 and 017 define the boundary: `DesktopRuntime` remains the local Wanix adapter, RuntimeRegistry selects providers, and Wanix is one provider among native and browser execution.

### Wanix namespace and host boundary

- Wanix exposes processes, terminals, VMs, browser services and storage as files in a composable namespace.
- OPFS provides browser-persistent storage; it remains subject to eviction and is not the canonical workspace store.
- Remote namespace import uses 9P over WebSocket. Whether a remote namespace is a runtime provider, resource provider or both is an orchestration decision.
- Wanix's host-exported devices and `#web` services provide the existing file-service boundary. The capability host ABI must map onto that boundary with scoped leases, not add an unrestricted host syscall surface.
- A namespace import grants only the files or capabilities exposed by that namespace. It does not grant workspace ownership, device trust or capabilities outside the mounted namespace.

## Runtime provider responsibilities

A provider is responsible for:

- creating, starting, suspending, stopping and destroying runtime instances;
- reporting lifecycle and observed status;
- executing workloads within its declared capability envelope;
- reporting failures with typed errors;
- enforcing runtime-level isolation and resource limits.

A provider is not responsible for:

- workspace identity or desired state;
- device identity, discovery or pairing;
- capability authorization;
- workspace persistence or synchronization;
- controller arbitration;
- display discovery or transport selection;
- orchestration or placement policy.

## Wanix packaging

Wanix and any selected engine or task driver must be reproducible and auditable:

- pin the Wanix module to an exact commit or pseudo-version;
- vendor Go modules with `go mod vendor`;
- build `wanix.wasm` and companion JavaScript in a controlled container or pinned toolchain;
- record the Go version, build flags, source commit, and output checksums;
- include the build recipe and SBOM entry under ADR-003;
- replace any CDN-loaded runtime artifact with the locally built bundle;
- verify offline startup and integrity before execution.

Updates require a new pin, checksum, SBOM diff and runtime regression run. A floating `@latest` or unversioned CDN URL is not permitted.

## Execution engines and task drivers

The runtime provider owns engine choice. AirDesk does not mandate a single Wasm engine.

- **Wanix task drivers:** `gojs`, WASI and JavaScript workers are the initial portable drivers; v86 is an optional legacy x86 driver. A driver is qualified per platform and per workload.
- **WASI 0.2:** baseline target for new portable applications. The documented Wanix `wasi` driver is `wasip1`; if the selected driver cannot execute a required component world, the provider must report it as unsupported rather than silently downgrade.
- **WASI 0.3:** evaluation target. Wasmtime 46+ and jco support it; adopt only after Wanix integration, toolchain, memory and startup gates pass.
- **WASIX:** vendor extension, not a baseline. Admit only for a named Wasmer workload.
- **WAMR / Wasmtime / wazero:** qualification candidates where a named workload exposes a gap. Wasmtime is the likely path for Component Model worlds that the browser Wanix driver cannot run.
- **v86:** only for a legacy x86 workload that cannot be rebuilt or emulated more narrowly. It is a task driver, not a second workspace or display authority.

Adopting an additional engine or driver requires a bundle-size measurement, startup benchmark, fidelity tests and failure-mode tests. “Available” is not a product requirement.

## FFI strategy

UniFFI is the primary cross-language binding layer for Rust transport, serialization and future RDP cores. Gomobile remains limited to Go/Wanix boundaries where it is the natural fit.

High-frequency pointer and terminal events must not cross FFI one call at a time. The boundary accepts batched or framed updates and leaves per-event processing on one side. FFI calls must have measured latency and allocation budgets before Trial promotion.

## Asset delivery

The app and Cast receiver bundle:

- the pinned Wanix WASM/JS runtime;
- the shell and generated TypeScript bundles;
- wterm, its selected core, and optional just-bash assets once adopted;
- required fonts, workers and WASI modules;
- checksums or integrity metadata used by the loader.

The runtime must not fetch executable code from a CDN in production. Network use is limited to session transport and explicitly configured remote runtimes. Offline startup must be tested after a cold install with networking disabled.

## Puter disposition

Puter is removed.

- Delete the Puter adapter, bundled assets and demo fixtures.
- Do not link Puter into any runtime path.
- Do not treat Puter as a fallback when Wanix fails.
- Do not cite Puter behavior as a compatibility requirement.
- Any UI pattern already adopted is documented in AirDesk design material, not carried as Puter code.

Wanix parity is measured against product requirements, not Puter behavior.

## Acceptance gates

- Native execution works on a supported platform without Wanix installed.
- A browser provider can execute a supported web application without owning workspace state.
- Pinned, vendored Wanix builds reproduce the committed WASM checksum.
- Cold start, compile time, memory and OPFS persistence meet the agreed Wanix budget.
- Application manifests resolve a declared WASI world and version; unsupported worlds fail closed with typed errors.
- Wanix's documented `wasi` driver is verified as `wasip1`; WASI 0.2 worlds run only through a qualified driver/toolchain.
- WASI Preview 1 adaptation, WASI 0.2 worlds and any claimed WASI 0.3 support are tested separately; none is inferred from another.
- WASIX is absent unless admitted for a named workload.
- The default single-threaded browser profile starts without `SharedArrayBuffer`; the threaded profile requires `crossOriginIsolated` and falls back explicitly.
- `crossOriginIsolated` and required headers are verified in WKWebView and Cast where threaded Wanix runs.
- A 9P namespace import or export is scoped to its mount and cannot bypass capability leases or workspace authority.
- Offline startup succeeds with no executable CDN dependency.
- Runtime state transitions are provider-defined and exposed through the ADR-017 contract.
- The runtime reports capabilities truthfully; absence is handled without UI or transport branching.
- No Wanix or runtime implementation source is fetched at runtime, and SBOM entries match the shipped artifacts.
- No Puter code, assets or adapter remain in the shipped product.
- Provider failure leaves workspace desired state intact.

## Consequences

- The runtime layer has multiple implementations but one provider contract.
- Wanix is treated as a namespace/task runtime, not a WASI-only sandbox, so its 9P and task-driver capabilities can serve later releases without redefining the provider contract.
- Native platform functionality remains available without Wanix.
- Wanix packaging and SBOM maintenance add release work.
- Reproducible WASM builds and offline startup remain hard requirements for Wanix.
- Demand-driven engines keep the support matrix small but delay optional workloads until a real use case exists.
- WASI 0.2 worlds improve portability, but the Wanix driver and toolchain may not support every world on every platform.
- Keeping a single-threaded profile is less performant but avoids making `SharedArrayBuffer` availability a startup requirement.
- 9P namespace import gives a concrete remote-runtime mechanism but adds authorization, latency and failure-mode work.
- Removing Puter reduces runtime surface and eliminates a competing implementation.
- Bundling all assets increases app/Cast size but removes CDN availability, integrity and offline risks.

# ADR-004: Runtime providers and execution baseline

- **Status:** Proposed — packaging, provider and performance gates required
- **Date:** 2026-10-29
- **Updated:** 2026-11-03 — Wanix re-scoped as preferred provider; native and browser providers first-class
- **Scope:** Runtime provider model, Wanix packaging, WASI engines, mobile/web FFI, runtime assets, Puter disposition
- **Amends:** ADR-001 runtime implementation choice only; workspace, display and protocol authority comes from ADR-016/017
- **Supersedes:** None
- **Related:** ADR-001, ADR-003, ADR-006, ADR-007, ADR-009, ADR-014, ADR-017, ADR-018, ADR-019

## Decision

AirDesk uses a provider-neutral runtime model. Wanix is the preferred portable runtime provider, not the only runtime.

- Native platform execution is a first-class provider.
- Browser execution is a first-class provider for web applications and browser presentation.
- Wanix executes portable WASI workloads where its sandbox and namespace model fit.
- No device is required to install or run Wanix.
- A runtime provider binds to a workspace; it does not own workspace identity, persistence or orchestration.

The provider contract, registry and placement policy are defined by ADR-017.

### Wanix execution baseline

- Wanix executes inside the web runtime on iOS, and later inside Android WebView and a Cast receiver. It does not run as an in-process native Go runtime in the baseline.
- WASI Preview 1 is the supported execution target. WASI Preview 2 is demand-driven and requires a separate Wasmtime spike.
- `wazero` is the only baseline WASM engine inside Wanix. Wanix is the runtime; wazero executes WASI modules inside the Wanix Go runtime, not as a native iOS engine.
- WAMR, Wasmtime and v86 are not shipped until a concrete workload requires them and passes a qualification spike.
- Rust shared cores use UniFFI for Swift/Kotlin bindings. Gomobile is limited to Go/Wanix boundaries where no Rust boundary is appropriate.
- All runtime and terminal assets are bundled locally. No production path depends on a runtime CDN.
- Puter is removed entirely. It is not a production runtime, fallback, reference implementation, demo fixture or bundled asset.

ADRs 001 and 017 define the boundary: `DesktopRuntime` remains the local Wanix adapter, RuntimeRegistry selects providers, and Wanix is one provider among native and browser execution.

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

Wanix and wazero must be reproducible and auditable:

- pin the Wanix module to an exact commit or pseudo-version;
- vendor Go modules with `go mod vendor`;
- build `wanix.wasm` and companion JavaScript in a controlled container or pinned toolchain;
- record the Go version, build flags, source commit, and output checksums;
- include the build recipe and SBOM entry under ADR-003;
- replace any CDN-loaded runtime artifact with the locally built bundle;
- verify offline startup and integrity before execution.

Updates require a new pin, checksum, SBOM diff and runtime regression run. A floating `@latest` or unversioned CDN URL is not permitted.

## Execution engines

The baseline Wanix engine is wazero because it is pure Go, avoids CGO, and fits the Wanix execution model.

WAMR, Wasmtime and v86 remain **Hold** until a named workload requires them:

- **WAMR:** only for a C/AOT workload with demonstrated wazero gaps; requires iOS/Android embedding and memory review.
- **Wasmtime:** only for a WASI Preview 2 component requirement; requires browser/native integration and binary-size review.
- **v86:** only for a legacy x86 workload that cannot be rebuilt or emulated more narrowly.

Adopting an additional engine requires its own ADR update, bundle-size measurement, startup benchmark and failure-mode tests. “Available” is not a product requirement.

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
- `crossOriginIsolated` and required headers are verified in WKWebView and Cast where Wanix runs.
- Offline startup succeeds with no executable CDN dependency.
- Runtime state transitions are provider-defined and exposed through the ADR-017 contract.
- The runtime reports capabilities truthfully; absence is handled without UI or transport branching.
- No Wanix/wazero source is fetched at runtime, and SBOM entries match the shipped artifacts.
- No Puter code, assets or adapter remain in the shipped product.
- Provider failure leaves workspace desired state intact.

## Consequences

- The runtime layer has multiple implementations but one provider contract.
- Native platform functionality remains available without Wanix.
- Wanix packaging and SBOM maintenance add release work.
- Reproducible WASM builds and offline startup remain hard requirements for Wanix.
- Demand-driven engines keep the support matrix small but delay optional workloads until a real use case exists.
- Removing Puter reduces runtime surface and eliminates a competing implementation.
- Bundling all assets increases app/Cast size but removes CDN availability, integrity and offline risks.

# Runtime architecture

AirDesk uses runtime providers so workspace semantics do not depend on one execution engine.

## Provider contract

```text
RuntimeProvider
  id()
  capabilities()
  create(request)
  start(instanceId)
  suspend(instanceId)
  stop(instanceId)
  status(instanceId)
  execute(instanceId, request)
  destroy(instanceId)
```

Providers report lifecycle and failures through typed observed state. They do not own workspace identity, persistence, authorization or placement.

## Providers

| Provider | Use |
| --- | --- |
| Native | Native applications, platform APIs, hardware acceleration, background work |
| Wanix | Portable WASI workloads, virtual filesystem, shell, terminal and namespaced tasks |
| Browser | Web applications, browser tools, browser-side presentation |
| Remote | Remote Wanix over 9P, SSH-backed applications, RDP RAIL/Xpra adapters, later |

## Wanix position

Wanix is the preferred portable execution environment where its sandbox and namespace model fit. It is not required on every device and is not the orchestration or workspace authority.

Wanix is a Plan 9-inspired namespace and task system, not only a WASI wrapper. It is responsible for:

- task drivers for Go/TinyGo (`gojs`), WASI Wasm, JavaScript workers and optional v86 x86 Linux;
- a unified, composable namespace of files, tasks, terminals, VMs and browser services;
- virtual filesystem and namespace management, including OPFS-backed persistence;
- shell and terminal processes;
- import and export of remote namespaces over 9P/WebSocket;
- process lifecycle and runtime-level isolation;
- portable command-line tools;
- host capability integration through the authorized adapter.

Wanix is not responsible for workspace identity, device identity, discovery, pairing, persistence, synchronization, capability authorization, controller arbitration, display discovery, orchestration or fabric transport selection.

## WASI targets

| Target | Status | Notes |
| --- | --- | --- |
| WASI Preview 1 | Compatibility | Legacy modules may be adapted where the task driver supports them |
| WASI 0.2 Component Model worlds | Baseline target | `wasi-cli`, `wasi-http`, `wasi-filesystem`, `wasi-sockets`; requires a qualified driver/toolchain |
| WASI 0.3 | Evaluation | Stable since June 2026; Wasmtime 46+ and jco support it; not baseline until Wanix integration qualifies |
| WASIX | Vendor extension | Wasmer-specific; admitted only for a named workload |

Application manifests pin a world and version. Do not treat "WASI" as one target, and do not infer WASI 0.3 from WASI 0.2 metadata. Wanix's documented `wasi` driver is `wasip1`; WASI 0.2 depends on a qualified Component Model driver and toolchain.

## Remote namespaces

A Wanix namespace can be exported from one page or host and imported over 9P/WebSocket. For AirDesk, a remote namespace may be:

- a remote runtime provider;
- a resource provider;
- both, with explicit roles.

The namespace mount boundary is a capability boundary, not workspace authority. Imported files or task namespaces do not automatically grant host capabilities, device trust or workspace write access.

## Portability matrix

| Platform | Wanix target | Threading | `SharedArrayBuffer` | Notes |
| --- | --- | --- | --- | --- |
| iOS WKWebView | Bundled browser Wanix | Single-thread default | Gated by COOP/COEP | Threaded profile optional; retest current iOS Safari/WebKit |
| iPadOS WKWebView | Bundled browser Wanix | Single-thread default | Gated by COOP/COEP | Same as iOS |
| macOS WKWebView | Bundled browser Wanix | Single-thread default | Gated by COOP/COEP | COEP `require-corp` required for WebKit isolation |
| Android WebView | Browser Wanix | Single-thread default | Device- and WebView-dependent | Must qualify, not assumed |
| Cast receiver | Browser Wanix | Single-thread | Not assumed | Hardware qualification required |
| Safari browser | Browser Wanix | Single-thread fallback | Baseline with `require-corp` isolation | `credentialless` COEP is not available in WebKit |
| Chromium/Firefox browser | Browser Wanix | Threaded where isolated | Available with COOP/COEP | Not a reason to require threading |

Do not require `SharedArrayBuffer` for the default profile. If `crossOriginIsolated` is false or `SharedArrayBuffer` is unavailable, select the single-threaded profile and report it.

## Placement

Initial placement modes:

- local-preferred;
- explicit device;
- explicit runtime provider.

Automatic constrained placement is later. Placement considers compatibility, availability, capabilities, resources, latency, security, power and connectivity. Unsupported combinations fail closed.

## Remaining portability questions

Document per platform:

- which Wanix task drivers are available;
- WASI world and version support;
- threading and shared-memory limits;
- filesystem mapping and namespace import restrictions;
- process isolation;
- JIT/AOT restrictions;
- background execution limits;
- hardware acceleration.

# Fabric Dependency Pre-screen

- **Status:** R0 pre-screen — research only; no dependency is admitted
- **Date:** 2026-11-04
- **Parent:** `docs/planning/universal-compute-fabric-research.md`
- **Policy:** ADR-003 dependency admission and commercial licensing policy
- **Method:** Primary project pages and package registries reviewed on 2026-11-04; versions and terms must be re-checked at the exact pinned commit before any Trial or Adopt decision

## 1. Decision

All candidates remain **Spike** under ADR-003.

No candidate may enter the shipping client, the default build, or a production path from this pre-screen. The purpose is to identify which candidates deserve a time-boxed spike, which need legal or platform review first, and which should be rejected early.

## 2. Findings

| Candidate | License / distribution signal | Current capability signal | Research disposition |
| --- | --- | --- | --- |
| Iroh | MIT OR Apache-2.0; Rust crate `iroh` 1.4.1; MSRV 1.91 | P2P QUIC with public-key dialing; the crate documentation says connections normally use a home relay and fall back to relay servers when hole punching fails | **Hold for a direct-path spike.** The relay behavior conflicts with ADR-013's no-hidden-relay baseline unless the spike proves a relay-free or explicitly authorized deployment |
| Loro | MIT; `loro-swift` MIT, core/FFI 1.17.1 | Rust, JS/WASM and Swift bindings; automatic merge, snapshots, delta updates; Swift bindings are described as experimental and include binary-only targets | **Hold for a state spike.** Test the conflict corpus and binary-size/tooling cost before considering it for geometry or shared documents |
| elfconv | Apache-2.0 | AOT Linux/ELF to WebAssembly; project warns it is work in progress; current documented support is AArch64, with x86-64 under development; static binaries only; partial syscall support | **Reject as an x86 solution for now.** Keep as an AArch64 research note; do not assume x86-64 readiness |
| CheerpX | Proprietary; commercial license required for business use, self-hosting and redistribution; Community license is limited | x86 virtualization in the browser; current documented support is 32-bit x86 only; no 3D acceleration | **Reject from the client baseline unless a commercial agreement, App Store review and 64-bit requirement are resolved.** It is not an open-source dependency |
| WALI | MIT | Linux syscall interface for WebAssembly; research implementation with WAMR; not itself a checkpoint/restore system | **Hold for an execution spike.** Useful for Linux ABI portability, not for migration by itself |
| WAMR checkpoint/restore | Apache-2.0 (WAMR); the checkpoint PR is separate | Checkpoint/restore API work is an open, long-running PR; not a stable cross-runtime migration guarantee | **Do not rely on it for R4.** Treat as research evidence, not a product primitive |
| Wanco | License must be verified at the repository | WebAssembly AOT compiler with cross-CPU checkpoint/restore research support; forked from Wasker | **Research note only.** Not admissible until license, maintenance and reproducibility are verified |
| Xpra | Server GPLv2+; `xpra-html5` MPL-2.0; other clients have different licenses | Seamless per-window remote applications with persistent reattach; seamless server is not available on macOS or Windows; HTML5 client keeps windows inside the browser page | **Hold for a server-side Linux spike.** Do not link GPL server code into the iOS client; verify MPL obligations for the HTML5 client |
| IronRDP | MIT OR Apache-2.0; optional OpenH264 integration has separate notices and Cisco binary conditions | Modular Rust RDP with EGFX/RAIL; native, WASM and FFI surfaces | **Hold for a Windows remote-window spike.** Resolve H.264/OpenH264 distribution and patent terms before any shipping path |
| WebMCP | W3C Community Group draft, not a standard; Chromium early preview/origin trial; WebKit position is oppose | No cross-browser support; no iOS WKWebView path; requires a secure context | **Defer and reject as a Phase 1 dependency.** Use PTY/terminal observation and explicit approvals |

### R1 transport pre-screen

| Candidate | Platform signal | Harness signal | Disposition |
| --- | --- | --- | --- |
| WebSocket | Existing browser and WKWebView baseline; ordered TCP stream only | T1 loopback baseline runs on the Mac harness | Keep as the required fallback |
| WebTransport over HTTP/3 | Safari and iOS Safari support arrive in 26.4; caniuse lists iOS 26.4+, so iOS 17–26.3 need a fallback; caniwebview lists WKWebView iOS 26.4 but in-app behavior still needs a device check; secure context required | Deno 2.9.4 exposes client and server APIs only with `--unstable-net`; T2 loopback baseline recorded and is slower than T1 at every payload size | Hold for the iOS 18.6 baseline; revisit only for iOS 26.4+ or a native controller; unstable server API is harness-only |
| WebRTC data channels | RTCDataChannel is available in WKWebView since iOS 11; WebKit restricts host ICE candidates, so mDNS, server-reflexive candidates or TURN may be required; Safari can drop data channels silently under loss and needs heartbeats | T3 macOS WKWebView loopback passes with host candidates only; established RTT is near T1, but channel setup is 141–187 ms and reconnect is about 237 ms | Trial for long-lived sessions; repeat on iOS 18.6 and a labeled Wi-Fi/tailnet path before comparing with Iroh; test TURN and silent-drop recovery separately |
| Iroh/QUIC | Latest crate is 1.4.1, MIT OR Apache-2.0, MSRV 1.91.0; QUIC peer connections use public-key identity, hole punching and relay fallback; relay servers forward encrypted packets | No harness yet; a Rust spike can reuse the T1/T2 metric shape and report direct versus relayed paths | Hold until relay policy and distribution cost are accepted; do not make a public relay the hidden default |
| SSH/tmux | Existing native remote-terminal path | Existing smoke tooling; represents remote execution, not a browser transport | Keep as the remote-execution reference |

Matching T1 and T2 numbers across payload sizes is the first R1 comparison. Do not compare loopback, LAN, tailnet or relay runs without separate labels.

## 3. Consequences for the research plan

### Iroh is not a drop-in “direct” transport

Iroh's default model is direct where possible and relay-assisted where necessary. That is a legitimate design, but it is not the same as AirDesk's current "direct path, no hidden relay" rule.

The R1 spike must record:

- whether the candidate can run without the public relay service;
- what self-hosted relay operation would cost;
- whether relay use is visible to the user and covered by policy;
- whether a relay-free configuration still meets NAT traversal and reconnect needs.

If the answer requires a hidden public relay, Iroh is held or rejected for the current architecture.

### CheerpX is a commercial dependency, not an open-source fallback

CheerpX may be technically capable, but it cannot be treated like a permissively licensed library. A spike would need a commercial licensing decision, App Store distribution review, and confirmation that the required workload is 32-bit x86. Until then it is not a viable fallback for “run anything.”

### elfconv does not currently solve x86

The project's own warnings make x86-64 a future item. The research plan should not cite elfconv as evidence that cross-ISA x86 execution is solved. Test AArch64 only if that specific workload matters.

### Xpra and IronRDP have different integration boundaries

Xpra is promising for Linux persistence but its server is GPLv2+ and its seamless mode is not a macOS/Windows server feature. IronRDP is permissively licensed but its H.264 path has separate codec and patent obligations. Both need separate server-only or adapter-boundary designs.

### WebMCP is not an iOS option

WebKit's stated position is oppose, and Chromium support is an early preview. Agent supervision must remain based on PTY/terminal observation, approval actions and explicit capability leases.

## 4. Required follow-up

Before promotion from Spike:

- re-check the exact pinned version, commit and license;
- record SBOM and binary-size impact;
- add platform-fit evidence for WKWebView, iOS and the distribution target;
- add an exit strategy for every component that touches transport, state, runtime, compositor or terminal behavior;
- obtain legal review for copyleft, proprietary, patent-bearing codec or App Store-sensitive dependencies;
- update ADR-003 exceptions only with an owner and expiry or review trigger.

## 5. Sources

- WebTransport compatibility: <https://caniuse.com/webtransport>
- WKWebView WebTransport compatibility: <https://caniwebview.com/features/mdn-webtransport/>
- WebKit Safari 26.4 release: <https://webkit.org/blog/17862/webkit-features-for-safari-26-4/>
- RTCDataChannel compatibility: <https://caniwebview.com/features/mdn-rtcdatachannel/>
- WebKit RTCDataChannel host-candidate note: <https://bugs.webkit.org/show_bug.cgi?id=189503>
- Deno WebTransport example: <https://docs.deno.com/examples/web_transport/>
- Iroh crate: <https://crates.io/crates/iroh>
- Iroh documentation: <https://docs.rs/iroh/latest/iroh/>
- Iroh QUIC design: <https://docs.iroh.computer/protocols/using-quic>
- Loro repository: <https://github.com/loro-dev/loro>
- Loro Swift bindings: <https://github.com/loro-dev/loro-swift>
- Loro FFI: <https://github.com/loro-dev/loro-ffi>
- elfconv repository: <https://github.com/yomaytk/elfconv>
- CheerpX documentation: <https://cheerpx.io/docs>
- CheerpX licensing: <https://cheerpx.io/licensing>
- WALI repository: <https://github.com/Wasm-Thin-Kernel-Interfaces/WALI>
- Wanco repository: <https://github.com/tamaroning/wanco>
- Xpra repository: <https://github.com/Xpra-org/xpra>
- Xpra HTML5 client: <https://github.com/Xpra-org/xpra-html5>
- Xpra client/license matrix: <https://xpra-org.github.io/xpra/Usage/Clients.html>
- IronRDP repository: <https://github.com/Devolutions/IronRDP>
- IronRDP EGFX/OpenH264 notes: <https://docs.rs/ironrdp-egfx>
- WebMCP browser support summary: <https://docs.mcpbundles.com/guides/webmcp-browser-support>
- Chrome WebMCP guidance: <https://developer.chrome.com/docs/modern-web-guidance/guides/webmcp/webmcp>

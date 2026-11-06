# Fabric Dependency Pre-screen

- **Status:** R0 pre-screen — research only; no dependency is admitted
- **Date:** 2026-11-04; updated 2026-11-05 with the T4 tailnet and relay results, the SSH/tmux pre-screen, and the S2 reattach and termination baselines
- **Parent:** `docs/planning/universal-compute-fabric-research.md`
- **Policy:** ADR-003 dependency admission and commercial licensing policy
- **Method:** Primary project pages and package registries reviewed on 2026-11-04; versions and terms must be re-checked at the exact pinned commit before any Trial or Adopt decision

## 1. Decision

All candidates remain **Spike** under ADR-003.

No candidate may enter the shipping client, the default build, or a production path from this pre-screen. The purpose is to identify which candidates deserve a time-boxed spike, which need legal or platform review first, and which should be rejected early.

## 2. Findings

| Candidate | License / distribution signal | Current capability signal | Research disposition |
| --- | --- | --- | --- |
| Iroh | MIT OR Apache-2.0; Rust crate `iroh` 1.4.1; MSRV 1.91 | P2P QUIC with public-key dialing; T4 relay-free loopback and two-host tailnet pass with explicit direct IP addresses; the tailnet run used a Tailscale DERP underlay, so it does not prove direct NAT traversal; a forced relay-only run passes 90/90 through the public n0 relay, but does not prove automatic fallback or self-hosted relay operation; the crate documentation says real connections normally use a home relay and fall back to relay servers when hole punching fails | **Trial for a labeled direct-underlay and self-hosted-relay spike.** Relay-free addressing and the public relay path work, but the public relay default remains unaccepted under ADR-013, and direct underlay, automatic fallback, Swift integration, relay operation and distribution cost are still unproven |
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
| WebRTC data channels | RTCDataChannel is available in WKWebView since iOS 11; WebKit restricts host ICE candidates, so mDNS, server-reflexive candidates or TURN may be required; Safari can drop data channels silently under loss and needs heartbeats | T3 passes on macOS WKWebView and the iOS 18.6 simulator with host candidates only; established RTT is near T1, but channel setup is 141–193 ms and reconnect is 237–314 ms | Trial for long-lived sessions; repeat on the physical iPhone and a labeled Wi-Fi/tailnet path before comparing with Iroh; test TURN and silent-drop recovery separately |
| Iroh/QUIC | Latest crate is 1.4.1, MIT OR Apache-2.0, MSRV 1.91.0; QUIC peer connections use public-key identity, hole punching and relay fallback; relay servers forward encrypted packets | T4 loopback passes with direct `127.0.0.1` addresses, zero relay addresses, 30/30 delivery and 2.6–8.4 ms reconnect. T4 two-host tailnet also passes 30/30 with zero Iroh relay paths, direct Iroh p50 55–163 ms and reconnect 152–300 ms, but Tailscale reported DERP and no direct underlay. A forced relay-only run with IP transports cleared passes 90/90 through the public n0 relay at p50 108.8/106.1/183.9 ms for 64 B/1 KiB/16 KiB, with 1 relay path and 0 direct paths; it does not test automatic direct-to-relay fallback. No WKWebView or Swift path measured | Trial for a labeled direct-underlay and self-hosted-relay spike; hold the public relay default, automatic fallback, NAT traversal and distribution decision until separately proven |
| SSH/tmux | SwiftNIO SSH 0.15.1, SwiftNIO 2.104.0 and SwiftCrypto 4.5.2 are Apache-2.0; tmux is ISC; OpenSSH is BSD-style with no GPL code | Existing native PTY path with a pinned host key, Keychain password and tmux startup; S2 simulator-to-tailnet background reattach passes 3/3 at p50 6.9 s and max 8.2 s; app-termination cold recovery also passes 3/3 at p50 57.6 s and max 70.8 s, with 3/3 process survival and transcript truthfulness; the underlay was DERP-relayed, and physical-device and second-device behavior are not measured | Keep as the remote-execution reference, not an R1 browser transport; physical-device and second-device reattach remain open |

Matching T1, T2, T3 and T4 numbers across payload sizes is the first R1 comparison. Do not compare loopback, LAN, tailnet or relay runs without separate labels. SSH/tmux is a stream/session path and is not payload-comparable with the browser transports.

### SSH/tmux remote-execution pre-screen

**Disposition: Spike/reference.** SSH/tmux is already implemented as AirDesk's remote-execution path, but it is not a candidate for the R1 direct-transport decision and is not a fallback for the browser bridge.

Evidence reviewed in the current tree:

- **Client stack.** Native NIOSSH `0.15.1` over SwiftNIO `2.104.0` and SwiftCrypto `4.5.2`; no external SSH client or WKWebView dependency.
- **Session shape.** The app requests an `xterm-256color` PTY, starts at 80x24, sends window-change requests on resize, and defaults to `tmux new -A -s airdesk` as an SSH exec request. With an empty startup command it opens a plain shell instead.
- **Credentials and host identity.** The server host key is pinned and compared for exact equality; there is no `known_hosts` learning or trust-on-first-use path. The password is stored in the device Keychain. A private-key seed is available only through the debug UI-test environment, and the authentication delegate clears its in-memory secret after one offer.
- **Lifecycle.** Backgrounding stops the SSH session and marks it paused; returning to the foreground reconnects. Transport loss retries three times at 1, 2 and 4 seconds, then reports exit. S2 records 3/3 simulator background reattaches and 3/3 app-termination recoveries, with the tmux heartbeat process surviving and new output visible after each reconnect; the termination metric includes cold app launch and preview presentation. Physical-device behavior and second-device takeover are still unmeasured.
- **Security boundary.** The startup command is an explicit user-supplied remote exec string, so it should be treated as credentialed remote execution rather than a sandbox. No agent forwarding, port forwarding or SFTP surface is present. There is no SSH keepalive or host-key-rotation UX; long-idle NAT survival and rotation are open.
- **Tests and smoke coverage.** Unit tests cover PTY input, resize, startup exec, mismatched-host-key rejection and 64 KiB output chunking. UI tests cover typing, resize, one simulated reconnect and the S2 app-background and app-termination recovery paths. `scripts/real-ssh-smoke.sh` exercises a generated-key local Mac OpenSSH server and optional tmux from the iOS simulator. `scripts/research/run-ssh-reattach.sh` records the S2 simulator-to-remote-host run, including pinned host key, generated key, unique tmux session and heartbeat checks.
- **License fit.** Repository license files reviewed at the current upstream heads: SwiftNIO SSH, SwiftNIO and SwiftCrypto are Apache-2.0; tmux uses the ISC-style permissive notice; OpenSSH is BSD-style and states it contains no GPL code. This is compatible with client distribution, subject to the normal pinned-commit recheck and App Store export review.
- **Platform fit.** OpenSSH and tmux servers exist on macOS and Linux, and the iOS client runs in-process with no browser or iOS-version gate. Physical-device backgrounding, Keychain access over a real install and App Store encryption-export treatment remain unverified.

The pre-screen supports SSH/tmux as the remote-execution reference and as the baseline for S2. It does not support presenting tmux as a migration mechanism or as an R1 transport winner. S2 now records process survival, reattach/relaunch time and transcript truthfulness on a labeled tailnet path for both backgrounding and app termination, but the path was DERP-relayed and the runs used a simulator; physical-device, second-device and direct-underlay behavior still need evidence before stronger claims.

## 3. Consequences for the research plan

### Iroh is not a drop-in “direct” transport

Iroh's default model is direct where possible and relay-assisted where necessary. That is a legitimate design, but it is not the same as AirDesk's current "direct path, no hidden relay" rule.

The R1 spike must record:

- whether the candidate can run without the public relay service;
- what self-hosted relay operation would cost;
- whether relay use is visible to the user and covered by policy;
- whether a relay-free configuration still meets NAT traversal and reconnect needs.

If the answer requires a hidden public relay, Iroh is held or rejected for the current architecture.

The T4 loopback run answers the narrow local question: `RelayMode::Disabled` plus explicit direct addresses establishes and reconnects a QUIC pair without a relay. The T4 tailnet run extends this to two hosts and also passes with zero Iroh relay paths, but the tailnet underlay was DERP-relayed, so it does not prove direct NAT traversal or a relay-free end-to-end path. The authorized relay run clears IP transports on both ends and passes 90/90 through the public n0 relay, confirming that the relay path transports and reconnects. It is a forced relay-only run, not an observed direct-to-relay fallback, and it does not cover relay failure, migration or self-hosting. The next run must establish a direct Tailscale or LAN underlay, then exercise a genuine direct attempt with a blocked path to observe automatic fallback.

### CheerpX is a commercial dependency, not an open-source fallback

CheerpX may be technically capable, but it cannot be treated like a permissively licensed library. A spike would need a commercial licensing decision, App Store distribution review, and confirmation that the required workload is 32-bit x86. Until then it is not a viable fallback for “run anything.”

### elfconv does not currently solve x86

The project's own warnings make x86-64 a future item. The research plan should not cite elfconv as evidence that cross-ISA x86 execution is solved. Test AArch64 only if that specific workload matters.

### Xpra and IronRDP have different integration boundaries

Xpra is promising for Linux persistence but its server is GPLv2+ and its seamless mode is not a macOS/Windows server feature. IronRDP is permissively licensed but its H.264 path has separate codec and patent obligations. Both need separate server-only or adapter-boundary designs.

### WebMCP is not an iOS option

WebKit's stated position is oppose, and Chromium support is an early preview. Agent supervision must remain based on PTY/terminal observation, approval actions and explicit capability leases.

### SSH/tmux is a remote-execution reference, not a transport candidate

SSH/tmux must stay out of the T1/T2/T3/T4 payload comparison. Its R1 role is to anchor remote execution and the S2 reattach test. The pre-screen clears the license and platform questions for the current native path, and S2 passes 3/3 simulator background reattaches and 3/3 app-termination recoveries with process survival and truthful transcripts. Physical-device behavior, second-device takeover, long-idle NAT survival and a direct-underlay run remain unmeasured. Do not describe tmux as a migration mechanism until those outcomes are recorded.

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
- SwiftNIO SSH license: <https://github.com/apple/swift-nio-ssh/blob/main/LICENSE.txt>
- SwiftNIO license: <https://github.com/apple/swift-nio/blob/main/LICENSE.txt>
- SwiftCrypto license: <https://github.com/apple/swift-crypto/blob/main/LICENSE.txt>
- tmux license: <https://github.com/tmux/tmux/blob/master/COPYING>
- OpenSSH license: <https://github.com/openssh/openssh-portable/blob/master/LICENCE>
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

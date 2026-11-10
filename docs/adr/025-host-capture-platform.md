# ADR-025: Host capture and media pipeline platform

- **Status:** Accepted — iOS app-surface capture selected; media implementation gated by P5-02/P5-03
- **Date:** 2026-11-10
- **Deciders:** Engineering lead, iOS owner, media owner, security owner
- **Scope:** Initial host capture source, iOS ReplayKit boundary, encoder placement, capture lifecycle, deferred full-device and macOS paths
- **Supersedes:** None
- **Amends:** None
- **Related:** ADR-003, ADR-005, ADR-006, ADR-012, ADR-013, ADR-018, ADR-021, ADR-024

## Context

The current app target is iOS 17.5 with Mac Catalyst disabled. `ScreenCaptureKit` is a macOS API and therefore cannot be used by the current iOS host target. The media plan still needs a concrete capture platform before P5-02 writes an encoder pipeline.

The repository has three materially different possible host shapes:

- an iOS app that presents and captures an AirDesk-owned workspace;
- an iOS device that captures the whole display, including other applications;
- a separate macOS host agent that captures windows or displays;
- an external host process on another operating system.

Those shapes have different permission, lifecycle, memory and transport boundaries. Conflating them would produce a pipeline that claims capabilities it cannot provide. In particular:

- in-app ReplayKit captures only the AirDesk app's own surfaces, not the whole device;
- a Broadcast Upload Extension can capture the whole display, but runs in a separate, memory-constrained process and needs its own target, shared-container and transport/IPC decision;
- `ScreenCaptureKit` requires a macOS target;
- an external host process does not solve capture on iOS and remains a separate backend.

ADR-006 already assigns per-window macOS capture to a separate ScreenCaptureKit host agent. This ADR decides the first media implementation that fits the current iOS app without silently redefining that decision.

## Decision

### 1. Use in-app ReplayKit for the first iOS host capture path

The initial host capture source is `RPScreenRecorder.startCapture` in the AirDesk iOS app, capturing AirDesk-owned workspace surfaces.

- Capture starts only after explicit user action and an authorized display-capture capability lease.
- Capture stays in the app process so capture lifecycle, encoder ownership, capability checks and transport remain under one authority boundary.
- The user-visible ReplayKit recording indicator is expected and must not be suppressed.
- Capture stops on session end, explicit user stop, app termination, loss of the required lease, capture failure, or when the platform invalidates the capture session.
- Capture does not persist frames or audio, and frame contents are never logged.

This path intentionally does not claim whole-device capture.

### 2. Full-device broadcast capture is deferred

A Broadcast Upload Extension using `RPBroadcastSampleHandler` is the only viable route considered here for whole-display iOS capture. It is not part of the initial P5-02 implementation.

Adding it later requires an ADR amendment that defines:

- the extension target, entitlements and App Group/shared Keychain access;
- whether encoding occurs in the extension or in the app;
- the bounded IPC or in-extension transport path;
- how capability leases, identity and authority survive app suspension;
- memory-pressure behavior and extension termination recovery;
- a user-visible explanation of the difference between app-surface and whole-device capture.

No whole-device, other-app, system-UI or protected-content capture is claimed before that gate passes.

### 3. Do not use ScreenCaptureKit on the iOS target

`ScreenCaptureKit` is permitted only in a separate macOS host target. It must not be linked, conditionally compiled or hidden behind an iOS code path.

The macOS per-window host remains under ADR-006 and needs its own target, permissions, signing, distribution and qualification work. P5-02/P5-03 may define platform-neutral capture and encoder boundaries, but they do not create or claim a macOS host.

### 4. External host processes are a separate backend

A Linux/Windows/macOS external host process may later provide capture under ADR-006 and ADR-017. It is not the selected path for the current iOS app and does not satisfy P5-02 by being present on another machine.

### 5. Capture boundary

P5-02 introduces a small capture boundary in `AirDesk/Display`:

```text
ReplayKit capture
  -> DisplayCaptureSource (CMSampleBuffer/CVPixelBuffer)
  -> bounded encoder input
  -> VideoToolbox encoder
  -> existing display transport under ADR-005/ADR-013
```

Rules:

- `DisplayCaptureSource` is mockable; unit tests do not require a physical capture session.
- ReplayKit callbacks and VideoToolbox work stay off the main thread.
- The encoder input queue is bounded. A slow encoder drops frames and requests a keyframe; it never blocks the capture callback or grows an unbounded backlog.
- Capture and encoder resources are released on stop, failure and termination.
- HEVC hardware encoding is the preferred codec when capability detection confirms it; H.264 is the required fallback. AV1 remains detection-only research and is not claimed.
- `CVPixelBuffer`/`IOSurface` and pooled buffers are preferred to avoid avoidable full-frame copies. Format conversion may still be required. “Zero-copy” is not claimed until a measured pipeline demonstrates it.

### 6. Transport and protocol separation

This ADR selects a capture source; it does not define a new wire format. Encoded display frames use the existing display channel and capability-lease rules under ADR-005, ADR-012 and ADR-013.

P5-02 must not claim glass-to-glass latency, frame pacing, hardware codec support or remote-display quality. Those remain P5-03 and later qualification gates.

### 7. Project targets

P5-01 adds no new Xcode target and no capture code.

- P5-02 may add source files to the existing `AirDesk` target.
- A Broadcast Upload Extension or macOS host target requires a separate target decision and must not be added merely to make an API compile.
- `project.yml` remains the source of truth; generated project files stay untracked.

## Consequences

### Positive

- Uses an API available on the current iOS 17.5 target.
- Avoids a second process, shared-container IPC and extension memory limits for the first pipeline.
- Keeps capture, lease checks and transport in the same authority boundary.
- Allows mock-source unit tests and bounded-queue tests without physical capture hardware.
- Leaves the macOS per-window host and whole-device iOS broadcast path available as explicit, separately gated extensions.

### Negative

- Only AirDesk-owned surfaces are captured in the first implementation.
- The app must be active for the initial capture path; background or whole-device capture is not available.
- Protected or system content may be omitted by ReplayKit and cannot be promised.
- VideoToolbox may require pixel-format conversion, so the first pipeline may not be zero-copy.
- Adding whole-device capture later requires a target, IPC/transport and security review that this ADR does not perform.

## Options considered

| Option | Decision |
| --- | --- |
| In-app ReplayKit (`RPScreenRecorder`) | Selected for the first iOS implementation; captures AirDesk-owned surfaces only |
| Broadcast Upload Extension | Deferred; required for whole-display iOS capture, but needs a separate target, IPC/transport and suspension model |
| Separate macOS host with ScreenCaptureKit | Deferred to ADR-006 target work; valid for macOS windows, not the current iOS target |
| External host process | Deferred; does not provide iOS capture |
| ScreenCaptureKit in the iOS target | Rejected; unavailable on iOS |
| No capture pipeline | Rejected; P5-02/P5-03 would remain blocked and remote display claims would remain impossible |

## Acceptance gates

This decision is complete when:

- ADR-025 and the ADR index record the selected initial host path;
- the masterplan marks P5-01 as decided without claiming media implementation;
- no ScreenCaptureKit symbol, target or iOS fallback is introduced;
- P5-02 defines a mockable capture source, bounded encoder queue, typed failures and lifecycle cleanup before any physical-capture claim.

P5-02 must stop and amend this ADR if:

- in-app ReplayKit cannot supply the required AirDesk workspace surfaces;
- the required capture rate or pixel format cannot reach a hardware encoder within the measured memory budget;
- a product requirement needs whole-device or other-app capture;
- the implementation would require an extension or macOS target without a separate decision.

## Open questions

- Which exact ReplayKit capture dimensions and frame rate are supported on the oldest target devices?
- Does the first pipeline require a Metal/vImage conversion stage before VideoToolbox, and what is its measured cost?
- Which display channel payload and keyframe/recovery semantics should P5-02 freeze with fixtures?
- Should the first release expose app-surface capture only, or keep the control disabled until P5-03 pacing is available?

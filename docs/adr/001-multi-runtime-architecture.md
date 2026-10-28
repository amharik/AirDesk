# ADR-001: Multi-runtime desktop architecture

- **Status:** Accepted — revised after architecture review
- **Date:** 2026-10-28
- **Scope:** iOS/iPadOS, Google Cast receiver, future Android, future remote runtime
- **Implementation:** Phases 1–2 implemented and simulator-verified 2026-10-28; receiver hardware validation pending
- **Supersedes:** None

## Review summary

The original direction is sound: separate runtime placement from presentation and input,
make Cast receiver-hosted, and defer desktop video streaming until a real use case
requires it. The main risks were underspecified lifecycle and protocol contracts rather
than the high-level choice.

This revision makes the following changes explicit:

1. Separates a display profile (a resolved combination of independent axes) from the
   runtime, display, and input abstractions themselves.
2. Separates runtime capabilities from display/input capabilities; the original
   `DisplayCapabilities` mixed these concerns.
3. Defines a single session lifecycle, a runtime factory seam, and clear ownership
   boundaries so Cast never starts a local runtime accidentally.
4. Tightens Cast protocol semantics: negotiated protocol versions, session generation,
   readiness, idempotent control messages, input acknowledgements, reconnect
   reconciliation, and bounded message validation.
5. Makes input delivery explicitly at-most-once across reconnects unless the receiver
   confirms otherwise. Acknowledgements are diagnostic/flow-control signals, not
   permission to blindly replay clicks or key events.
6. Treats receiver persistence and capability reports as observed facts, not assumptions.
   A reported storage API does not prove durable workspace persistence.
7. Adds testable acceptance criteria and a phased implementation order that keeps Android
   and remote streaming out of the critical Cast fix.

## Context

AirDesk currently assumes that exactly one Wanix runtime lives on the iOS device.
`SessionCoordinator.performConnection` creates a local runtime and loads the local
`DesktopSurface`, even when the selected target is a Google Cast receiver. The receiver
also runs its own shell, so a Cast session can start two runtimes.

Runtime placement, display target, and input routing are only partially separated. This
couples connection setup to local runtime creation and makes receiver-hosted Cast, Android
standalone rendering, and future remote execution harder to add safely.

The architecture must support:

1. Wanix running on the iOS/iPadOS device, presented on the phone or a supported external
   display.
2. Wanix running on a Cast receiver, controlled by the phone.
3. Wanix running on an Android device, with the desktop presented on its own screen or an
   attached display.
4. A future remote Wanix runtime, potentially with a separate frame transport.

The design must not imply that every device/display combination is supported. A profile is
valid only when the selected runtime, display path, and input path are available and their
capabilities are sufficient.

## Decision

1. **Cast is receiver-hosted for the MVP.** The receiver owns and runs the desktop runtime.
   The phone sends normalized input and session/control messages. Do not encode and stream
   the desktop in this path.
2. **Android is standalone.** The Android device owns its runtime. Use an Android activity
   or `Presentation` for the applicable display. Do not add a framebuffer transport for a
   local HDMI path.
3. **Video/WebRTC is deferred.** Define seams that do not prevent it, but implement frame
   transport only when a concrete remote-execution, unsupported-device, or network-sharing
   use case justifies it.
4. **Runtime location, display target, and input route are independent axes.** Resolve them
   into a `DisplayProfile` before connecting. The controller UI may render capabilities and
   status, but must not branch its layout on runtime location.
5. **Session orchestration is separate from runtime implementation.** `SessionCoordinator`
   owns session lifecycle and selects an endpoint; it does not directly construct a
   concrete runtime or attach a local surface for every target.
6. **Platform validation is path-specific.** Apple TV/AirPlay validates the applicable
   external-scene and mirroring behavior; USB-C/HDMI validates wired display behavior;
   Cast hardware validates the receiver-hosted runtime. These are not interchangeable
   tests.
7. **Fail closed on invalid or unsupported remote messages.** Protocol version, message
   shape, session identity/generation, and input values are validated at the receiving
   boundary.

## Consequences

### Positive

- The normal Cast path needs no desktop video encoder.
- Cast cannot accidentally create a second local runtime when profile resolution and
  runtime creation are enforced as acceptance-tested invariants.
- The controller can remain mostly target-agnostic while still exposing target-specific
  capabilities and recovery state.
- Android can reuse shell assets and protocol schemas without reusing iOS display code.
- A future streamed target can add a frame transport without forcing frame delivery into
  the runtime-control interface.

### Negative and trade-offs

- Cast workspace state is receiver-owned; continuity across receivers or devices is not
  automatic.
- Receiver CPU, memory, WASM support, browser APIs, storage behavior, and lifecycle must be
  tested on actual hardware.
- iOS and Android require platform-specific display implementations.
- `SessionCoordinator` becomes an orchestrator and must have explicit lifecycle/state
  transition tests.
- A common input schema does not guarantee identical input semantics across all runtimes;
  unsupported events must be rejected or reported rather than silently reinterpreted.

## Non-goals

- WebRTC, VideoToolbox, or remote framebuffer implementation.
- RDP/RAIL or remote application-window streaming.
- General-purpose transport/plugin framework.
- Cross-device workspace synchronization or migration.
- Guaranteed background execution by iOS or a Cast receiver.
- Full Android implementation details in this ADR.

## Target model

```text
SessionCoordinator
  ├─ ProfileResolver       requested target + discovered capabilities -> DisplayProfile
  ├─ RuntimeEndpoint       start / input / control / state / stop
  ├─ DisplayCoordinator   local iOS scene and surface presentation only
  └─ InputTransport       local or remote delivery of normalized InputEvent
```

`DisplayProfile = RuntimeLocation + DisplayTarget + InputRoute + required capabilities`

The axes are independent types, but not every Cartesian-product combination is valid.
`ProfileResolver` must reject invalid combinations with a typed error rather than relying
on UI conditionals.

| Profile | Runtime location | Display target | Input route | Runtime/workspace authority |
| --- | --- | --- | --- | --- |
| Preview | iOS device | Phone | Local surface | iOS runtime |
| iOS extended | iOS device | External scene | Local surface | iOS runtime |
| iOS mirrored | iOS device | Mirrored phone | Local surface | iOS runtime |
| Cast | Cast receiver | Cast receiver | Cast channel | Receiver owns desktop/workspace; phone owns controller UI |
| Android standalone | Android device | Android activity / `Presentation` | In-process | Android runtime |
| Future remote | Remote host | Local stream or remote display | Remote channel | Remote host, subject to an explicit authority model |

The phone may retain the client-side session identifier and controller state while
connected to Cast, but it does not own the receiver filesystem or imply that receiver
workspace state is backed up. Do not describe this as synchronized state.

## Proposed types and boundaries

These are illustrative contracts; adapt names to existing project types rather than
introducing duplicate enums or wrappers unnecessarily.

> Implementation note: the project already has a `RuntimeCapabilities` type with desktop,
> terminal, filesystem, and similar feature flags. Do not declare a second Swift type with
> the same name. Extend or rename the existing feature-capability type, then add the
> lifecycle/persistence capabilities described below under a distinct name if both are
> needed.

```swift
enum RuntimeLocation: String, Codable, Sendable {
    case phone
    case castReceiver
    case androidDevice
    case remote
}

enum DisplayTarget: String, Codable, Sendable {
    case phone
    case externalScene
    case mirroredPhone
    case castReceiver
    case androidPresentation
    case stream
}

enum InputRoute: String, Codable, Sendable {
    case localSurface
    case castChannel
    case inProcess
    case remoteChannel
}

struct DisplayProfile: Equatable, Sendable {
    let runtime: RuntimeLocation
    let target: DisplayTarget
    let input: InputRoute
}

enum PersistenceMode: String, Codable, Sendable {
    case opfs
    case indexedDB
    case memory
    case unknown
}

struct RuntimeCapabilities: Codable, Equatable, Sendable {
    var supportsWorkspaceSelection: Bool
    var supportsSuspendResume: Bool
    var persistence: PersistenceMode
}

struct InputCapabilities: Codable, Equatable, Sendable {
    var supportsPointer: Bool
    var supportsKeyboard: Bool
    var supportsTextInput: Bool
}

struct DisplayCapabilities: Codable, Equatable, Sendable {
    var width: Double
    var height: Double
    var scale: Double?
    var supportsExternalPresentation: Bool
}
```

Capability models should reflect actual existing project requirements. Do not add fields
that no caller consumes. Runtime capabilities, input capabilities, and display capabilities
are reported separately; combine them only in the resolved profile or diagnostics view.

`ProfileResolver` is a pure function over the requested target and discovered platform/
device capabilities. It must return either a valid profile or a typed resolution error. The
controller can display capability labels, but its layout must not depend on
`RuntimeLocation`.

## Runtime seam

`DesktopRuntime` remains the local Wanix/Puter adapter interface. Add a session-facing
endpoint so the coordinator can control local and receiver-hosted runtimes through one
lifecycle contract.

```swift
struct RuntimeContext {
    var sessionId: String
    var workspace: Workspace
    var appearance: String
}

enum RuntimeControl {
    case workspace(Workspace)
    case appearance(String)
    case suspend
    case resume
    case shutdown
}

@MainActor
protocol RuntimeEndpoint: AnyObject {
    var location: RuntimeLocation { get }
    var state: RuntimeState { get }
    var capabilities: RuntimeCapabilities { get }
    var onStateChange: ((RuntimeState) -> Void)? { get set }

    func start(context: RuntimeContext) async throws
    func send(_ event: InputEvent)
    func sendControl(_ control: RuntimeControl)
    func stop() async
}
```

The production implementation should use project-native types for `RuntimeState`,
`Workspace`, and `InputEvent`. If a transport needs serializable representations, define
protocol DTOs at the transport boundary; do not assume an in-memory Swift model is a wire
format.

Implementations:

- `LocalRuntimeEndpoint`: wraps `SurfaceRuntimeHost` and `DesktopRuntime`.
  `WanixRuntimeAdapter` and `PuterRuntimeAdapter` remain implementation details.
- `CastRuntimeEndpoint`: starts/resumes a receiver session, waits for the receiver's
  readiness handshake, sends input/control messages, and maps receiver state/errors into
  `RuntimeState`.
- `AndroidRuntimeEndpoint`: future implementation for the Android-owned runtime; it is not
  part of the Cast fix.
- `RemoteRuntimeEndpoint`: future implementation only after a remote use case and its
  security/transport model are selected.

`SessionCoordinator` obtains an endpoint from a small factory keyed by the resolved profile.
Do not build a generic dependency-injection or transport-plugin framework for this. Do not
add `sendFrame` to `RuntimeEndpoint`; a future `FrameTransport` is an independent concern.

## Session lifecycle and ownership

Use one session lifecycle with target-specific states/details rather than a separate,
partially overlapping state machine for every transport. Exact enum names may follow the
existing code, but transitions must be testable.

```text
idle
  -> resolvingProfile
  -> connecting
  -> startingRuntime / waitingForReceiverReady
  -> ready
  -> recovering
  -> ready | failed | ending
  -> ended
```

Required invariants:

- Resolve and validate the profile before creating a runtime or attaching a desktop
  surface.
- A Cast profile must never create `LocalRuntimeEndpoint`, `DesktopRuntime`, or a local
  `DesktopSurface` runtime.
- `ready` means the selected runtime has acknowledged that it is ready to accept input; a
  loaded web page or connected Cast session alone is insufficient.
- Only the endpoint selected for the active profile receives input.
- Ending a session stops input immediately. Runtime shutdown and receiver retention are
  explicit lifecycle decisions, not side effects of UI dismissal.
- All asynchronous completions must be checked against the active session ID/generation so
  a late callback from a previous connection cannot mark a newer session ready.
- `stop()` and `sessionEnd` must be idempotent. Repeated disconnect/cleanup callbacks must
  not double-release or restart resources.

## Disconnect and resume policy

For Cast, the receiver may keep its runtime alive for a short, bounded grace period after
sender disconnect, if the platform lifecycle permits it. The initial grace period should
be configurable and measured; do not promise persistence across receiver restarts or
process termination.

On reconnect:

1. Reconnect to the receiver and verify protocol compatibility.
2. Send `sessionResume` with the same session ID and the last acknowledged input sequence,
   plus the client session generation/token described by the protocol.
3. Receiver responds with current runtime state and its last accepted input sequence.
4. Reconcile state. Do not replay pointer/key/button events whose execution status is
   ambiguous. If the receiver no longer has the session, start a new receiver session and
   report that continuity was lost.

Local-runtime recovery may retain the existing four-attempt exponential backoff, provided
attempts are cancelled on session end and stale completions are ignored.

## Display seam

`DisplayCoordinator` remains responsible for iOS scene discovery, mirroring detection, and
external `UIWindow` management. It must not choose or instantiate the runtime.

- For local iOS targets, it attaches/detaches `DesktopSurface` after the profile has
  selected a local endpoint.
- For Cast, there is no local desktop attachment; the receiver owns presentation.
- For Android, the Android activity/`Presentation` owns presentation.
- `DisplayModeResolver` remains the pure source of truth for local iOS mode resolution.

Do not force every target into a common `present(view:)` protocol. The shared layer is
profile selection, session lifecycle, capability reporting, and input semantics—not
rendered content.

## Input contract

`InputTransport` is already close to the required boundary. Extract the current nested
`SessionInputTransport` if useful and use `InputRoute` for route selection. Keep
transport-specific delivery details out of the controller UI.

Rules:

- Pointer coordinates are normalized to `0...1` in a documented viewport coordinate space.
  Define whether the origin is top-left and how letterboxing/rotation is handled; convert
  to receiver coordinates at one boundary only.
- Every input event has a session ID/generation and monotonically increasing sequence
  number. Sequence numbers must not be reused within a session generation.
- Pointer-move events may be coalesced. Button transitions, key-down/key-up, text commits,
  and other state-changing events must not be coalesced in a way that changes semantics.
- The receiver validates event type, coordinate range, payload size, and sequence/session
  identity before dispatch.
- An ack reports the highest contiguous sequence accepted by the receiver. This is the v2
  format; the receiver may aggregate the shell's current per-event acknowledgements into
  `lastAcceptedInputSeq` before forwarding it.
- Missing acknowledgements are diagnostics and may trigger reconnect/reconciliation. They
  do not authorize blind replay of potentially non-idempotent input.
- Input queue length and payload sizes are bounded. When backpressured, coalesce pointer
  moves first and surface a recoverable error if non-coalescible events cannot be
  delivered.
- Text input is a text-commit operation, not an implicit simulation of arbitrary keyboard
  events. Keep keyboard events and text commits distinct.
- Cast input uses `urn:x-cast:com.airdesk.input`. Control/session state uses
  `urn:x-cast:com.airdesk.control`.

## Cast protocol v2

The existing `CastControlMessage` is version 1 and sends session/appearance/workspace.
Version 2 adds a readiness handshake, capabilities, runtime state, acknowledgements, and
resume reconciliation. Treat these payloads as protocol examples; implement typed DTOs and
shared test vectors rather than constructing unvalidated dictionaries throughout the
codebase.

### Protocol rules

- The sender and receiver negotiate supported protocol versions at session start. Reject
  unsupported major versions with a structured error; ignore unknown optional fields for
  the same compatible major version.
- Every session-scoped message includes `sessionId` and a monotonically increasing
  `generation` or equivalent session epoch. Reject stale generations and mismatched session
  IDs.
- Every message has a bounded serialized size and a known type. Validate required fields and
  types before acting.
- Control operations that may be retried (`sessionStart`, `sessionResume`, `appearance`,
  `workspace`, `sessionEnd`) must be idempotent or carry an operation ID so duplicate
  delivery is safe.
- The receiver must not claim durable persistence merely because OPFS/IndexedDB is
  available. `persistence` describes the storage mode actually selected by the runtime;
  durability and backup are separate properties.
- Error messages use stable machine-readable codes plus safe diagnostic text. Never send
  filesystem paths, secrets, or unfiltered exception details to the controller.

### Sender to receiver

```json
{
  "version": 2,
  "type": "sessionStart",
  "sessionId": "session-...",
  "generation": 1,
  "operationId": "op-...",
  "workspace": "default",
  "appearance": "dark",
  "protocol": { "input": 1, "control": 2 }
}
```

```json
{
  "version": 2,
  "type": "sessionResume",
  "sessionId": "session-...",
  "generation": 1,
  "lastAckedInputSeq": 421
}
```

Also supported: `appearance`, `workspace`, `sessionEnd`, `ping`. Each state-changing
control should include an `operationId` where duplicate delivery could otherwise repeat a
side effect.

### Receiver to sender

```json
{
  "version": 2,
  "type": "ready",
  "sessionId": "session-...",
  "generation": 1,
  "receiverVersion": "1",
  "width": 1920,
  "height": 1080,
  "persistence": "opfs",
  "capabilities": {
    "pointer": true,
    "keyboard": true,
    "textInput": true,
    "desktopWindows": true
  },
  "lastAcceptedInputSeq": 0
}
```

Also supported: `state`, `viewport`, `ack`, `notice`, `error`, `pong`. The exact ack
payload must follow the single acknowledgement model chosen for the input contract.

## Readiness and recovery semantics

- The receiver sends `ready` only after the runtime is initialized and can accept input; it
  must not infer readiness from iframe load alone.
- The sender marks the session ready only after receiving a valid `ready` for the active
  session ID/generation.
- Receiver `state` messages drive Cast runtime state on the phone. State messages from stale
  sessions are ignored.
- `sessionEnd` disables input immediately. The receiver may retain the runtime during the
  bounded reconnect grace period, then stop it.
- On resume, the receiver reports whether the same runtime/session was recovered and its
  last accepted input sequence. If not recoverable, return a specific error or require a
  new `sessionStart`; do not silently pretend continuity.
- `ping`/`pong` may support liveness diagnostics but are not proof that the runtime is
  healthy or ready.

## Receiver shell bridge

The shell currently posts `ready`, `viewport`, `ack`, `state`, `notice`, and `error` to the
native `WKScriptMessageHandler`. Inside the receiver iframe there is no native handler, so
those messages do not reach `receiver.js` through that path.

Add an explicit receiver host mode to `bridge.js`:

- `?host=cast` selects the Cast receiver bridge path instead of the native WebKit message
  handler.
- `post()` uses `window.parent.postMessage(message, expectedOrigin)` with an explicit,
  configured target origin; do not use `*` for a privileged control channel.
- `receiver.js` listens for messages from the expected iframe window and expected origin,
  validates schema and active session ID/generation, then forwards valid messages over the
  control channel.
- The receiver sets `host=cast` on the iframe URL and configures the expected origin from
  trusted deployment configuration.
- If the shell and receiver are same-origin, still validate `event.source` and message
  shape. If cross-origin, configure the exact allowed origin.
- Never treat a `postMessage` event as trusted solely because its payload contains a
  valid-looking `sessionId`.

This bridge is required for truthful `ready`, `ack`, and runtime-state behavior. Without
it, the receiver must not claim the sender has received those signals.

## Profile resolution and connection flow

Resolve the requested target before runtime creation:

```text
requested target + discovered device/display capabilities
  -> ProfileResolver
  -> valid DisplayProfile or typed error
  -> RuntimeEndpointFactory
  -> endpoint.start(context)
  -> endpoint reports ready
  -> attach local presentation if the profile requires it
  -> ready
```

Initial profile mapping:

```text
preview                 -> phone runtime + phone target + local surface
external/wired/AirPlay  -> phone runtime + resolved local display target + local surface
Cast                    -> Cast receiver runtime + Cast target + Cast input channel
future Android          -> Android runtime + Android presentation + in-process input
future remote           -> remote runtime + explicitly selected input/frame paths
```

Do not infer all AirPlay targets as extended or mirrored without consulting the existing
`DisplayModeResolver`. Keep local mode resolution behavior unchanged during the
seam-extraction phase.

For Cast:

```text
idle -> resolvingProfile -> connecting -> waitingForReceiverReady -> ready
                                                    |                  |
                                                    v                  v
                                                  failed           recovering
                                                                       |
                                                               ready / failed
```

Cast must not start local Wanix as a fallback. If the receiver cannot run the runtime, show
a receiver-specific failure and offer a separately initiated local-preview action only if
product behavior explicitly allows it. Never silently change runtime authority under an
active session.

## File-level implementation plan

### Phase 0 — Contract and baseline

- Keep this ADR as the source of architecture decisions.
- Capture current behavior in tests before refactoring: preview, extended, mirrored, Cast,
  reconnect, and runtime teardown.
- Document the receiver hosting URL, configured origins, registered Cast application ID,
  and protocol channel names separately from the ADR. Do not invent deployment values.
- Define typed protocol DTOs and shared JSON test vectors for the sender and receiver.

### Phase 1 — Extract seams without behavior change

Potential new files (adapt to existing layout and avoid duplicate types):

- `AirDesk/Models/DisplayProfile.swift`: axis enums, profile, and pure profile resolution.
- `AirDesk/Runtime/RuntimeEndpoint.swift`: `RuntimeContext`, `RuntimeControl`,
  `RuntimeEndpoint`.
- `AirDesk/Runtime/LocalRuntimeEndpoint.swift`: wraps `SurfaceRuntimeHost` and
  `DesktopRuntime`.
- `AirDesk/Input/SessionInputTransport.swift`: extract the current nested transport and use
  `InputRoute`.

Likely changed files:

- `AirDesk/Session/SessionCoordinator.swift`: resolve profile first; own an endpoint rather
  than directly owning `(any DesktopRuntime)?`; guard asynchronous callbacks by session
  ID/generation.
- `AirDesk/App/AppEnvironment.swift`: wire endpoint factory and Cast control callbacks.
- `AirDesk/Display/DisplayModeResolver.swift`: add tests but preserve current resolution
  behavior.
- `AirDesk/Models/DisplayDevice.swift`: add only metadata needed by profile resolution.
- `project.yml`: run `xcodegen generate` after adding files.

Tests:

- `DisplayProfileTests`: valid/invalid target combinations resolve deterministically.
- `SessionRuntimeRoutingTests`: preview/extended/mirrored use `LocalRuntimeEndpoint`.
  Phase 1 preserves the existing Cast compatibility path; the no-local-runtime assertion
  moves to Phase 2.
- Existing `DisplayModeResolverTests`, `InputDispatcherTests`, and recovery tests remain
  green.
- Add stale-callback and idempotent-stop tests.

### Phase 2 — Receiver-hosted Cast

Potential new files:

- `AirDesk/Cast/CastRuntimeEndpoint.swift`
- `AirDesk/Cast/CastProtocol.swift` (or extend `CastMessage.swift` with typed v2 envelopes)

Likely changed files:

- `AirDesk/Session/SessionCoordinator.swift`: remove local runtime creation for Cast; wait
  for valid receiver `ready`; use receiver state for recovery.
- `AirDesk/Cast/CastSessionCoordinator.swift`: expose control receive, ready/state/error
  callbacks, and resume reconciliation.
- `AirDesk/Cast/GoogleCastAdapter.swift`: parse control messages in addition to input
  messages.
- `AirDesk/Cast/CastMessage.swift`: add v2 types or migrate to `CastProtocol`.
- `AirDesk/Input/InputEvent.swift`: add the session generation field with a backward-
  compatible decode default, then validate it at the input boundary.
- `AirDesk/Resources/DesktopShell/bridge.js`: add the explicit `host=cast` parent-message
  path.
- `CastReceiver/receiver.js`: validate bridge messages; send `ready`; forward
  `ack`/`state`/`viewport`/`error`; handle resume; reject incompatible versions.
- `CastReceiver/README.md`: document protocol, lifecycle, persistence limitations, and
  origin configuration.

Tests:

- `CastProtocolTests`: encode/decode valid messages; reject malformed payloads, unsupported
  versions, stale generations, and mismatched sessions.
- Extend `CastSessionCoordinatorTests`: handshake, duplicate control messages, receiver
  ready, disconnect, resume, runtime-lost recovery, and teardown.
- Receiver JavaScript tests/smoke test: shell ready and input ack reach the sender only
  through the configured bridge.
- Native test: a Cast session does not create a local `DesktopSurface` runtime.
- `SessionRuntimeRoutingTests`: Cast never uses `LocalRuntimeEndpoint`.
- Input tests: sequence handling, pointer-move coalescing, and no blind replay of ambiguous
  state-changing events.

### Phase 3 — Android standalone (separate milestone)

- Decide repository placement only when Android implementation begins.
- Reuse shell assets and versioned input/control schemas where appropriate.
- Implement Android controller UI and an activity/`Presentation` for the desktop.
- Use an in-process input bridge for a local HDMI path; no network transport is required for
  that path.
- Validate WebAssembly and persistence support on actual target devices before claiming
  parity.
- Add Android Cast receiver support only if a separate product requirement justifies it.

### Phase 4 — Hardware validation and diagnostics

- iOS external display: test wired display dimensions, orientation, disconnect/reconnect,
  and local runtime teardown.
- AirPlay/Apple TV: test external-scene and mirroring paths independently; include
  1080p/4K where supported.
- Google Cast: test discovery, receiver startup, runtime CPU/memory, WASM behavior, actual
  persistence after reload/restart, input latency, background/foreground, disconnect grace
  period, reconnect, and runtime loss.
- Android: test display discovery, activity/`Presentation` lifecycle, WebView WASM and
  storage APIs.
- Record runtime location, profile, receiver version, protocol version, readiness latency,
  input ack latency, recovery outcome, and persistence mode in diagnostics. Avoid logging
  sensitive input payloads.
- Mark a capability as verified only after the relevant hardware test has passed.

## Security and privacy

- Validate protocol version, session ID/generation, message shape, size limits, and
  `InputEvent.validated()` at the receiver boundary. Keep native input validation as the
  single native gate and add equivalent receiver-side validation.
- Scope Cast custom-channel messages to the active Cast session, but do not treat channel
  scoping as user authentication or authorization for arbitrary receiver APIs.
- Restrict `postMessage` by exact origin and source window; do not expose receiver control
  namespaces to arbitrary web origins.
- Avoid placing long-lived secrets in protocol messages or URLs. Use platform-supported
  session mechanisms where available and document the actual trust boundary of Cast
  pairing/session ownership.
- A future remote transport requires an explicit pairing/authentication model, TLS,
  authorization, replay protection, and threat review before it is enabled.
- Bound event queues and message sizes to limit resource exhaustion. Do not forward
  unfiltered runtime errors or filesystem details to the controller.
- Do not log raw keyboard/text content by default. Diagnostics should use event types,
  sequence numbers, timing, and error codes.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Cast receiver cannot run Wanix within CPU/memory limits | Spike early on real hardware; keep receiver shell minimal; define a supported capability floor and fail clearly below it |
| Receiver storage is ephemeral or not durable across restart | Report the actual storage mode; test reload/restart; describe workspace loss honestly; add snapshots only as a separately scoped feature |
| Cast control/input channel drops | Explicit ack semantics, bounded queues, resume reconciliation, visible recovery UI; never blindly replay ambiguous input |
| A late callback revives an ended session | Check session ID/generation at every async callback and test stale callbacks |
| `postMessage` bridge is spoofable or misconfigured | Exact target origin, source-window validation, schema validation, no wildcard origin for control messages |
| AirPlay external-scene behavior varies | Hardware matrix; keep mirroring fallback where supported; do not infer one mode from another |
| Android WebView lacks required APIs | Validate WebAssembly, OPFS/IndexedDB, and external display behavior on target devices before committing to parity |
| Transport abstraction becomes over-generalized | Keep the endpoint contract small; do not add a generic plugin registry or frame API prematurely |
| Protocol drift between iOS and receiver | One versioned schema document, typed DTOs, shared test vectors, compatibility tests |

## Acceptance criteria

### Phase 1 — Seam extraction

- Existing preview, AirPlay, wired, and mirroring behavior is unchanged.
- Profile resolution is deterministic and tested for supported and rejected combinations.
- Asynchronous callbacks from a stale session cannot alter the active session.
- `xcodegen generate` succeeds and the full iOS test suite passes.

### Phase 2 — Receiver-hosted Cast

- A Cast session starts no local Wanix runtime and attaches no local desktop surface.
- Receiver `ready` is required before the controller marks the session ready.
- Protocol messages with invalid versions, malformed fields, mismatched session IDs, or
  stale generations are rejected.
- Input acknowledgements have one documented meaning; reconnect does not blindly replay
  ambiguous input.
- Resume either recovers the same receiver session with reconciled state or explicitly
  reports that continuity was lost.
- Session end immediately disables input and cleanup is idempotent.
- Shell-to-receiver bridge messages use the configured origin and are covered by tests.
- README/backlog claims match verified hardware behavior.

### Later Android/remote milestones

- Android implementation is not considered complete until its runtime, presentation, and
  persistence behavior pass a device matrix.
- Remote streaming is not considered supported until frame transport, security,
  performance, and failure recovery have a separate ADR and acceptance suite.

## Open questions

1. Is receiver-local workspace continuity sufficient for the Cast MVP, or must the phone
   seed/export a workspace snapshot? Default recommendation: receiver-local workspace is
   sufficient for the first milestone; do not imply cross-device continuity.
2. Should Android live in this repository or a separate one? Defer until the Android
   milestone; decide based on build/release ownership, not this ADR.
3. What are the production HTTPS receiver URL, configured shell origin, and registered Cast
   application ID? Must be supplied by deployment configuration before end-to-end
   validation.
4. Which Apple TV, wired display, and Cast hardware are available for validation? Record
   exact models/OS versions in test results.
5. When both are supported, should AirPlay default to extended desktop or mirroring?
   Preserve current resolver behavior until product requirements and hardware tests support
   a change.
6. What reconnect grace period is appropriate for Cast? Measure receiver lifecycle behavior
   first; use a bounded configurable value and document that process/receiver restarts can
   still lose the session.

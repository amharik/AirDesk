# ADR-019: Application model and lifecycle

- **Status:** Proposed — manifest and lifecycle gates required
- **Date:** 2026-11-03
- **Updated:** 2026-11-03 — peer review: manifest schema and sandboxed lifecycle transitions with quotas
- **Updated:** 2026-11-03 — peer review round 3: lifecycle maps to `observedState`; presentation attribute; cooperative checkpoints; quota enforcement matrix
- **Deciders:** Product owner, engineering lead
- **Scope:** Application manifests, instances, desired/observed state, runtime requirements, lifecycle, remote applications
- **Supersedes:** None
- **Amends:** ADR-001, ADR-007
- **Related:** ADR-004, ADR-010, ADR-012, ADR-016, ADR-017, ADR-018

## Context

Applications currently exist as desktop shell entries and runtime-specific integrations. Their identity depends on whether they are built-in, Wanix-backed or terminal-backed. That prevents runtime replacement, placement and a consistent shell presentation.

The blueprint makes applications first-class workspace entities with provider-neutral manifests and lifecycle semantics.

## Decision

### 1. Application identity is provider-neutral

An application manifest describes:

```text
AirDeskApplicationManifest
  id, version, name
  entrypoint
  runtimeTargets[]
  requiredCapabilities[]
  presentation
  permissions[]
  lifecycle
```

```text
RuntimeTarget
  provider: native | wanix | browser | remote
  world: wasip1 | wasi-cli@0.2 | wasi-http@0.2 | wasi-filesystem@0.2 | wasi-sockets@0.2 | wasi-cli@0.3 | ...
```

Release 1 qualification is explicit: `provider: wanix` targets `wasip1`; `provider: native` targets `wasi-cli@0.2` (with `wasi-cli@0.3` as a later qualified option). A target whose `(provider, world)` pair is not qualified is unsupported and is not placed.

An application may be:

- native;
- web;
- Wanix/WASI;
- remote;
- built into AirDesk.

WASI applications pin a Component Model world and version. A bare `wasi` target is not sufficient. Preview 1 targets are an explicit compatibility target, not an alias for a 0.2 world. WASIX is a named vendor target, not a fallback.

The manifest does not name a specific device or runtime instance.

### 2. Instances have desired and observed state

```text
ApplicationInstanceDefinition
  id, applicationId
  desiredState: running | stopped | suspended
  placement
  configuration
```

```text
ApplicationInstanceStatus
  instanceId
  observedState: starting | running | suspended | stopped | failed | unavailable
  runtimeProviderId
  runtimeInstanceId
  deviceId
  lastHeartbeat
  lastError
```

Desired state belongs to the workspace manifest. Observed state belongs to the orchestrator's runtime view. They must not be merged.

### 3. Lifecycle is standardized

```text
installed -> available -> starting -> running -> suspended -> stopped
                                      \-> failed
                                      \-> unavailable
```

- `unavailable` means no provider or device can currently realize the instance.
- `failed` means a provider attempted realization and reported an error.
- A failed or unavailable instance remains in the workspace with its definition.
- Recovery is a reconciliation outcome, not a manifest rewrite.

### 3.1 Sandbox lifecycle and quotas

The orchestrator drives a deterministic lifecycle for sandboxed (Wanix/Worker/iframe) applications:

```text
RESOLVED
  -> MOUNTING_CAPABILITIES
  -> ACTIVE
  -> SUSPENDED_CHECKPOINTED
  -> TERMINATED
```

- `RESOLVED`: manifest verified, runtime target and world resolved, no resources yet.
- `MOUNTING_CAPABILITIES`: capability leases issued and validated; failure here returns to `TERMINATED` with a typed error and no partial mount.
- `ACTIVE`: running and eligible for presentation; input is delivered only when the presentation attribute is `foreground`.
- `SUSPENDED_CHECKPOINTED`: execution stopped after an app-cooperative checkpoint; resuming must not duplicate side effects.
- `TERMINATED`: all capability handles, workers, streams and leases are revoked deterministically.

**Foreground/background is not a lifecycle state.** It is a presentation attribute (`presentation: foreground | background`) owned by the display session. `ACTIVE_FOREGROUND → ACTIVE_BACKGROUND` changes only that attribute; `observedState` remains `running`. Input is withheld in the background.

Mapping to the workspace `observedState` (section 2):

| Sandbox state | `observedState` |
| --- | --- |
| `RESOLVED`, `MOUNTING_CAPABILITIES` | `starting` |
| `ACTIVE` | `running` (with `presentation` attribute) |
| `SUSPENDED_CHECKPOINTED` | `suspended` |
| `TERMINATED` | `stopped` |
| mount/placement error | `failed` or `unavailable` with a typed reason |

Rules:

- Every transition is explicit and observable; the shell never infers lifecycle from DOM or process state.
- `SUSPENDED_CHECKPOINTED` is **app-cooperative**. The application must implement the checkpoint/restore contract in its runtime ABI. The orchestrator does not take process snapshots, does not capture JS heap or Web Worker state, and does not claim `SUSPENDED_CHECKPOINTED` for an application that cannot checkpoint. Such an application is `TERMINATED` (or left `ACTIVE` if it cannot be stopped safely) and restored from its declared durable state.
- Per-application quotas bound worker count, memory, CPU time, open handles, stream buffers and persisted bytes.
- Exceeding a quota moves the application to `failed` with a typed error; it does not silently degrade the workspace.
- Termination revokes capability handles before releasing resources, and is idempotent.
- A background application cannot request new capabilities without returning to the foreground authorization path.

### 3.2 Quotas are enforced only where the provider can enforce them

Quotas are not a wish list. The manifest declares `quotas`, and each provider declares which dimensions it can actually enforce:

| Provider | Workers | Memory | CPU time | Handles/streams | Persisted bytes |
| --- | --- | --- | --- | --- | --- |
| Wanix / Worker | Yes (worker count) | Yes (WASM linear-memory cap) | Yes (instruction/time budget) | Yes | Best effort (OPFS quota) |
| Native agent | Yes (process/session count) | Yes (`rlimit`/cgroup) | Yes (CPU shares or wall clock) | Yes | Yes (volume quota) |
| WKWebView iframe | Yes (declared) | No | No | Partial (message/stream count) | Best effort (WebKit quota) |
| Remote application | Provider-reported | Provider-reported | Provider-reported | Provider-reported | Provider-reported |

Placement is **fail closed**: if a manifest requires a quota dimension the candidate provider cannot enforce, the orchestrator does not place the instance. It reports `unavailable` with `QuotaUnenforceable` and the missing dimensions. A provider must never accept a placement and silently ignore a quota dimension. Remote providers must return a signed or attested enforcement statement; absent one, the instance is treated as unable to enforce.

The manifest carries the quota and schema fields required by this machine:

```text
AirDeskApplicationManifest
  schemaVersion
  id, version, name
  entrypoint
  runtimeTargets[]        -> provider, world@version, architectures[]
  requiredCapabilities[]  -> cap_uri@version, scope
  presentation
  permissions[]
  quotas                  -> workers, memoryBytes, cpuMillis, handles, persistedBytes
  quotaEnforcement[]      -> required dimensions the provider must be able to enforce
  lifecycle
```

### 4. The shell uses a common application abstraction

The AirDesk Shell presents applications through a provider-neutral interface:

- application identity and icon;
- window and presentation metadata;
- lifecycle actions (open, focus, suspend, stop, restore);
- capability request prompts;
- error and unavailable states.

The shell must not depend on Wanix internals, runtime-specific DOM or a provider-specific process model.

### 5. Runtime requirements are declarative

- An application declares runtime requirements and required capabilities.
- The orchestrator selects a compatible provider and placement.
- An application that cannot be placed remains `unavailable`; it must not be silently run on an incompatible provider.
- Capability requirements are authorized separately from runtime availability.

### 6. Remote applications use the same model

Remote applications are provider adapters, not a separate workspace model.

- RDP RAIL, Xpra, SSH-backed terminals and similar integrations implement presentation/execution adapters.
- Remote application protocols are advertised through AD-CAP; the orchestrator selects a compatible provider.
- Remote window/session persistence is reported truthfully. Prefer Xpra-style reattach, where the application survives client disconnect.
- Remote application windows use the same window and lifecycle abstractions.
- Remote execution is explicit, not an implicit consequence of display connectivity.
- Remote application support is post-MVP.

### 7. Application data and resources are references

- Application instance data is referenced through workspace resource references.
- An application definition does not embed a device-local absolute path as its only identity.
- Resource access policy is separate from runtime placement.
- Uninstalling or stopping an application does not silently delete referenced resources.

## Consequences

### Positive

- Applications can move between compatible providers later.
- The shell is less runtime-specific.
- Remote applications can integrate without changing workspace identity.
- Desired and observed state have clear ownership.
- Runtime failure can be reported without losing application definitions.

### Negative

- Requires application packaging and compatibility rules.
- Requires a stable lifecycle and error contract.
- Adds manifest and migration work.
- Some current built-in applications need adapter shims before they fit the model.

## Acceptance gates

- An application manifest validates without naming a device or runtime instance.
- The orchestrator can place an instance on a compatible provider.
- Observed state transitions do not rewrite desired state.
- A provider failure leaves the application definition intact and reports `failed` or `unavailable`.
- The shell uses the provider-neutral application/window abstraction.
- Required capabilities are authorized separately from runtime availability.
- An incompatible provider fails closed rather than silently substituting.
- Sandboxed applications traverse the explicit `RESOLVED → MOUNTING_CAPABILITIES → ACTIVE ↔ SUSPENDED_CHECKPOINTED → TERMINATED` lifecycle, and that state maps deterministically to `observedState`.
- Foreground/background changes the `presentation` attribute without changing `observedState`, and background input is withheld.
- `SUSPENDED_CHECKPOINTED` is entered only after an app-cooperative checkpoint; no process or heap snapshot is claimed.
- Per-application quotas are enforced only on providers whose enforcement matrix covers the required dimensions; exceeding one produces `failed` with a typed error and no silent degradation.
- A placement whose required quota dimension is unenforceable fails closed with `QuotaUnenforceable`.
- A WASI application declares a world and version; unsupported worlds or versions fail closed.
- Remote application adapters do not change the workspace identity model.
- Remote application protocol selection comes from AD-CAP facts, not a hard-coded workspace branch.

## Options considered

| Option | Why not chosen |
| --- | --- |
| Shell-specific application registry | Not provider-neutral; every new runtime would edit the shell |
| Treat foreground/background as lifecycle states | Conflates presentation with process state and makes recovery ambiguous |
| OS process snapshots for suspend/resume | Not available in iOS sandboxes or Web Workers, and would claim state the runtime cannot guarantee |
| Desired/observed state plus app-cooperative checkpoints | Chosen: providers can tell the truth, and unsupported checkpoints fail explicitly |
| Enforce every quota on every provider | Some providers cannot enforce memory or CPU; pretending otherwise hides overcommit |

## Out of scope

- An app store or distribution marketplace.
- Arbitrary live process migration.
- Cross-device application data synchronization.
- Multi-user application permissions.
- Third-party application sandbox certification.

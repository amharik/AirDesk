# Product vision

AirDesk is a distributed personal workspace. It brings the capabilities of a user's devices into one coherent computing environment without replacing their operating systems.

The workspace is the persistent logical environment. Devices provide resources. Native agents expose those resources. Runtime providers execute workloads. Display endpoints present the workspace. AirDesk orchestrates the relationships between them.

## What AirDesk is

- A software layer that coordinates applications, workloads, input, displays, storage and device capabilities.
- A personal workspace that survives device, runtime and display changes.
- A fabric that lets a phone, tablet, Mac, browser endpoint or TV contribute specific capabilities.
- A system that can run locally without cloud connectivity.

## What AirDesk is not

- A universal operating system.
- A remote-desktop client that streams one machine's desktop as the default product.
- A cloud workspace that requires a coordinator for local use.
- A multi-user collaboration product in its first releases.
- A system that requires Wanix on every device.

## Product relationship

```text
Workspace -> Orchestration -> Devices, Capabilities and Runtime Providers -> Applications and Presentation
```

The workspace is the persistent environment. The orchestrator decides how it is realized. Devices contribute hardware, native functionality and execution resources. Runtime providers execute applications. The shell presents the workspace. Sessions connect displays and controllers.

## Prior art and differentiation

Apple Continuity is the closest reference for positioning: Universal Control, Sidecar and Continuity Camera each solve one bounded cross-device job rather than merging the operating systems. That validates the Release 1 → 2 sequence and the rule that devices contribute capabilities instead of being replaced.

AirDesk differs by being the open, heterogeneous equivalent:

- works across device vendors and operating systems;
- does not require an Apple account or a single-vendor ecosystem;
- keeps the workspace independent of the display and device;
- exposes capability and protocol boundaries that third parties can implement.

AirDesk should adopt the bounded-job pattern, not imitate OS-level integration that depends on platform-private APIs.

## Standards posture

- Prefer WASI 0.2 Component Model worlds for portable applications.
- Treat WASIX as a vendor extension, not a portability baseline.
- Treat WebTransport as a qualified browser transport, not a requirement.
- Use WebAuthn/FIDO2 as the future reference for user identity, separate from device keys.
- Prefer 9P for Wanix namespace import/export where it fits, rather than inventing a parallel remote filesystem protocol.

## Initial market

The first useful product is a stable personal workspace on a single device. The device fabric follows only after that workspace is coherent, recoverable and independent of a display session.

## Success condition

A user can open a workspace, use applications, disconnect a display or device, reconnect elsewhere, and recover the same logical workspace without losing its identity or desired state.

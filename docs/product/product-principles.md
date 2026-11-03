# Product principles

1. **Workspace first.** The persistent logical environment matters more than the device, runtime or display currently realizing it.
2. **Local first.** A workspace must remain usable without cloud connectivity or cross-device synchronization.
3. **Native capability, not native replacement.** AirDesk uses each platform's security, permissions and native functionality rather than pretending every device is the same.
4. **Wanix where it fits.** Wanix is the preferred portable runtime, not a universal requirement.
5. **Presentation is replaceable.** A display session presents a workspace; it does not own it.
6. **Explicit placement.** Remote execution is a deliberate choice, not a hidden consequence of connecting a display.
7. **Permission is not availability.** A device advertising a capability does not grant access to it.
8. **Trust is not collaboration.** Pairing a device does not make it a workspace owner or a collaborator.
9. **Multiple controllers, one workspace.** Several devices may control one personal workspace without creating multiple owners.
10. **Truthful recovery.** The product reports what was restored, restarted, reconnected or lost.
11. **No premature distribution.** Do not introduce CRDTs, a general scheduler or cloud synchronization before the local workspace is dependable.
12. **Fail closed.** Unsupported versions, unauthorized operations and invalid state produce typed errors, not silent fallbacks.
13. **Standards first, vendor extensions second.** Target WASI 0.2 worlds and qualified web standards; admit WASIX or a vendor protocol only for a named workload.
14. **Degrade explicitly.** If `SharedArrayBuffer`, WebTransport, a WASI world or a remote protocol is unavailable, select the documented fallback and report it.

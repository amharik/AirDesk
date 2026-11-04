# Fabric Threat-Model Delta

- **Status:** R0 draft — security review required before any spike reaches Trial
- **Date:** 2026-11-04
- **Parent:** `docs/planning/universal-compute-fabric-research.md`
- **Existing model:** `docs/architecture/security-model.md`
- **Scope:** Incremental threats introduced by remote execution, host handoff, browser endpoints, remote windowing, synchronization and agent supervision

## 1. Purpose

The current security model covers the local workspace, device identity, capability leases and the loopback presentation endpoint. The universal compute fabric adds new data paths and trust boundaries.

This document lists the new threats and the gates a research spike must satisfy. It does not replace the existing security model or authorize any implementation.

## 2. New trust boundaries

| Boundary | New risk |
| --- | --- |
| Workspace host to remote execution provider | Command execution, data exfiltration, provider impersonation, resource exhaustion |
| Device to device synchronization | Unauthorized state disclosure, replay, rollback, merge corruption |
| Workspace host handoff | Stale or malicious host claiming authority, lost updates, credential exposure |
| Browser endpoint to local host agent | Origin confusion, token theft, DNS rebinding, local service abuse |
| Remote application host to client | Malicious window metadata, clipboard leakage, input injection, codec attack surface |
| Agent or terminal to workspace actions | Prompt injection, destructive commands, approval bypass, secret leakage |
| Cross-ISA/runtime sandbox to host | Sandbox escape, syscall abuse, unsafe host mounts, untrusted binary execution |
| Transport adapter to relay or discovery service | Metadata leakage, hidden relay dependency, denial of service |

## 3. Assets

- Workspace identity, manifest, layout and desired state.
- Device identity keys, pairing state and host epoch.
- Capability grants, leases and revocation state.
- SSH credentials, host keys, passwords and session tokens.
- Terminal output, prompts, commands, clipboard and file contents.
- Remote application surfaces and window metadata.
- Agent instructions, approvals, diffs and audit records.
- Resource references and provider-local paths.
- Transport metadata, endpoint identifiers and connection patterns.

## 4. Threats and mitigations

### T1 — Remote execution is treated as trusted local execution

Threat: a remote provider receives broader files, credentials or host access than the user intended.

Required controls:

- Capability-scoped leases for every remote operation.
- Explicit placement with provider and device identity shown in diagnostics.
- No implicit filesystem, clipboard or keychain forwarding.
- Typed denial when a lease, quota or provider version is invalid.
- Remote output is untrusted data, not executable UI.

Gate: a denied capability must fail before the remote command is launched.

### T2 — Remote command construction enables injection

Threat: host, path, agent name or environment values are interpolated into a shell command.

Required controls:

- Structured argument arrays, never string concatenation for untrusted values.
- Bounded, validated identifiers.
- No shell metacharacter pass-through unless the operation is explicitly a shell session.
- Approval and audit for destructive operations.

Gate: adversarial provider names, paths and arguments cannot alter the command being executed.

### T3 — Host handoff permits rollback or a second writer

Threat: an old host or attacker presents a stale manifest and resumes authority.

Required controls:

- `host_epoch` fencing and expected-revision checks.
- Signed transfer, integrity hash and explicit user initiation.
- Staged import followed by activate; no silent promotion.
- Returning old host demotes to read-only.
- Force takeover reports lost mutations.

Gate: a stale, replayed or interrupted handoff cannot produce two writers.

### T4 — Synchronization leaks or corrupts workspace state

Threat: offline edits, replayed updates or malicious peers expose data or converge to an unsafe state.

Required controls:

- Authenticated and encrypted transport.
- Device-bound authorization and revocation.
- Explicit merge classes; `manual` for identity, ownership, placement and security.
- Conflict corpus and migration tests.
- No whole-workspace CRDT by default.

Gate: duplicate, replayed, out-of-order and unauthorized updates fail or remain manual.

### T5 — Browser endpoint escapes its loopback boundary

Threat: a web page reaches the local host agent, reuses a token, or becomes workspace authority.

Required controls:

- Loopback-only binding and strict origin/port checks.
- Per-session token and capability boundary.
- COOP/COEP/CSP and no broad `unsafe-inline`.
- No DNS rebinding path; reject unexpected `Host` and `Origin`.
- Browser storage remains evictable and non-authoritative.

Gate: cross-origin, non-loopback and expired-token requests fail closed.

### T6 — Remote window metadata is trusted

Threat: a malicious host sends oversized titles, spoofed identities, unsafe geometry or input-capture requests.

Required controls:

- Treat remote window titles, app identity and geometry as untrusted network input.
- Bound and sanitize strings; validate geometry and z-order.
- Separate remote surface identity from local authority.
- Release all pressed inputs on disconnect, blur or generation change.
- Clipboard, audio, file and drive redirection stay off by default.

Gate: malformed or oversized remote-window messages cannot crash or take focus.

### T7 — Codec or remote-window dependency creates a distribution problem

Threat: H.264/OpenH264 or a GPL component imposes patent, notice, source-offer or App Store obligations that were not planned.

Required controls:

- ADR-003 review before any codec or server component is Trial.
- Prefer a server-side process boundary for GPL code.
- Record Cisco/OpenH264 binary conditions and notices where used.
- Do not bundle components that cannot be distributed lawfully.

Gate: license and distribution review passes before a codec enters the client.

### T8 — Agent supervision enables destructive actions or prompt injection

Threat: an agent or remote process convinces the user to approve a destructive action, leaks secrets, or acts without an audit trail.

Required controls:

- Human approval for destructive or irreversible actions.
- Clear provenance and scope for each approval.
- Terminal/PTY observation as the default; no WebMCP dependency.
- Redact credentials and sensitive input from logs.
- Audit accepted and rejected actions.

Gate: no destructive operation without an explicit user decision and audit record.

### T9 — Cross-ISA or namespace sandbox escapes

Threat: a translated binary, syscall shim or remote namespace gains host access beyond its mount or lease.

Required controls:

- Capability-scoped namespace mounts.
- No host filesystem or device exposure by default.
- Treat cross-ISA as untrusted code execution.
- Resource and process limits.
- Fail closed on unsupported syscalls or worlds.

Gate: the workload cannot access a resource outside its declared namespace or lease.

### T10 — Transport or discovery leaks metadata or relies on a hidden relay

Threat: a transport dependency discloses peer identifiers, connection patterns or content through a relay not covered by policy.

Required controls:

- No plaintext outside loopback.
- Relay use is explicit, authorized and visible.
- Self-hosted or disabled relay configurations must be measurable.
- Discovery advertisements carry no stable device ID, secret or role mask.
- Treat unknown certificate hashes as untrusted.

Gate: a direct-path claim is false if the test traffic traverses an unapproved relay.

## 5. Research gates

Before a spike reaches Trial:

- [ ] Threat-model delta reviewed by the security owner.
- [ ] New data path and trust boundary diagram updated.
- [ ] Capability and lease requirements named.
- [ ] Credential storage and logging reviewed.
- [ ] Failure and revocation tests defined.
- [ ] License and distribution review completed where relevant.
- [ ] Abuse cases added to the scenario corpus.

## 6. Open questions

- Does the device fabric permit any relay, and under what user-visible policy?
- Can remote terminal output be treated as untrusted while still supporting copy/paste and file transfer?
- What user approval is required for host handoff and force takeover?
- Which remote-window features are disabled by default: clipboard, audio, file transfer, microphone, camera?
- Does browser endpoint pairing require a QR bootstrap, a numeric code, or both?
- How are agent approvals bound to the exact command or diff shown to the user?
- What is the minimum audit record that is still privacy-preserving?

# Deployment topologies

AirDesk components are logical roles. A release may run them in one process or across devices.

## Topology 1 — Single native device

```text
Native shell + workspace store + orchestrator + session coordinator
  -> native and Wanix runtime providers
  -> local device agent
```

Release 1 uses this topology. It must be useful without a coordinator service, browser endpoint or network.

## Topology 2 — Native host with browser endpoint

```text
Browser endpoint <-> local host agent <-> workspace/orchestrator (host device)
```

The browser presents the workspace. The local agent exposes only scoped capabilities and host services. The browser is not workspace authority.

## Topology 3 — Personal device fabric

```text
Controller device <-> device fabric <-> workspace host
Capability providers, execution providers and display endpoints attach explicitly
```

Release 2 introduces agents, pairing, capability leases and multi-controller input. The coordinator may assist connectivity but is not required for local operation.

## Topology 4 — Optional coordinator-assisted

```text
Devices <-> coordinator (discovery, rendezvous, signaling, optional relay)
```

The coordinator is control-plane only. Local workspace operation continues without it where the released feature set allows. It must not own workspace state or capability grants.

## Topology 5 — Remote execution

```text
Workspace host -> remote runtime/application provider on another device
```

Remote placement is explicit. Quotas, network failures, capability availability and recovery must be visible to the user.

## Topology 6 — Shared workspace

```text
Multiple authenticated users -> shared workspace authority
```

This is Release 5. It requires membership, roles, permissions, revocation and audit before any shared CRDT or group-session work.

## Non-goals for early releases

- Cloud-hosted canonical workspaces.
- Transparent remote execution.
- Multi-tenant coordination.
- Browser-hosted workspace authority.
- Distributed consensus or scheduling.

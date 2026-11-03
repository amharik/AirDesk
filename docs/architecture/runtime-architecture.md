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
| Wanix | Portable WASI workloads, virtual filesystem, shell and terminal processes |
| Browser | Web applications, browser tools, browser-side presentation |
| Remote | Remote Wanix, SSH-backed applications, RDP RAIL/Xpra adapters, later |

## Wanix position

Wanix is the preferred portable execution environment where its sandbox and namespace model fit. It is not required on every device and is not the orchestration or workspace authority.

Wanix is responsible for:

- WASI/WASIX execution where supported;
- virtual filesystem and namespace management;
- shell and terminal processes;
- process lifecycle and runtime-level isolation;
- portable command-line tools;
- host capability integration through the authorized adapter.

Wanix is not responsible for workspace identity, device identity, discovery, pairing, persistence, synchronization, capability authorization, controller arbitration, display discovery, orchestration or fabric transport selection.

## Placement

Initial placement modes:

- local-preferred;
- explicit device;
- explicit runtime provider.

Automatic constrained placement is later. Placement considers compatibility, availability, capabilities, resources, latency, security, power, preferences and connectivity. Unsupported combinations fail closed.

## Portability

Document per platform:

- whether Wanix runs natively or in a browser environment;
- WASI/WASIX feature availability;
- threading and shared-memory limits;
- filesystem mapping;
- process isolation;
- JIT/AOT restrictions;
- background execution limits;
- hardware acceleration.

Do not assume uniform Wanix deployment across iOS, Android, desktop and browser.

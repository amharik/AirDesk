# Browser endpoint host protocol

Status: loopback host service, browser client/policy and app lifecycle wiring are implemented and tested behind [ADR-014](../adr/014-browser-endpoint-topology.md). A production browser page, reconnect UX, COOP/COEP isolation proof and non-loopback transport remain pending.

## Topology

The host is a presentation endpoint, not the workspace authority. It listens on IPv4 loopback only and serves one WebSocket path, `/endpoint` by default. The browser connects with `ws://127.0.0.1:<port>/endpoint?token=<token>`.

The listener binds `127.0.0.1`; it does not expose a LAN interface and does not provide TLS. The allowed `Origin` is configured separately and must also be loopback HTTP/HTTPS.

## Configuration

| Field | Rule |
| --- | --- |
| `path` | Starts with `/`; no query, fragment, backslash or control characters |
| `port` | `0` requests an ephemeral port |
| `token` | 16–4096 ASCII characters from `[A-Za-z0-9._~-]` |
| `tokenExpiresAt` | Handshake rejects an expired token |
| `allowedOrigin` | `http(s)://127.0.0.1:<port>` with no credentials, path, query or fragment |
| `heartbeatInterval` / `heartbeatTimeout` | Heartbeat may be disabled with `0`; a positive interval requires a positive timeout |
| `handshakeTimeout` | Positive, default 10 s |
| `maximumMessageBytes` | 1 KiB–1 MiB, default 64 KiB |

The host returns the bound address and port after startup. A failed or timed-out listener start is typed and does not leave a running listener.

## Handshake

The request must be:

- `GET` over HTTP/1.1
- the configured WebSocket path
- a valid `Host`
- `Upgrade: websocket`, `Connection: Upgrade` and `Sec-WebSocket-Version: 13`
- one valid `Sec-WebSocket-Key`
- exactly one `token` query parameter
- exactly one loopback `Origin` matching the configured origin

Rejections are fail-closed with typed HTTP status codes: `400`, `401`, `403`, `404`, `405`, `426` or `431`. Token comparison is constant-time. The server completes the RFC 6455 accept response only after all checks pass and the token is unexpired.

## Display messages

After the upgrade, browser clients may send JSON messages:

| Type | Meaning |
| --- | --- |
| `display.register` | Register a workspace/display session and initial viewport |
| `display.viewport` | Update a positive finite viewport |
| `display.focus` | Update or clear the focus target |

Every message must declare:

```json
{
  "role": "display",
  "authority": "none",
  "canWriteWorkspace": false,
  "workspaceId": "...",
  "displaySessionId": "...",
  "viewport": { "width": 1280, "height": 720 },
  "focusTarget": null,
  "generation": 0
}
```

Workspace and display-session identifiers are limited to 256 ASCII characters from `[A-Za-z0-9._:-]`. Viewport dimensions are finite and between 0 and 100,000; viewport updates must be positive. Focus targets are at most 512 bytes. A browser endpoint cannot claim authority or write workspace state.

The host rejects workspace/session mismatches, duplicate registration, stale generations, malformed frames, oversized frames and protocol violations with typed wire errors. Registration and display updates are surfaced through `onDisplayRegistered` and `onDisplayUpdated`; closure is surfaced through `onConnectionClosed`.

## Heartbeat and lifecycle

The host sends ping frames on the configured interval when heartbeats are enabled and closes a connection that misses the timeout. Server shutdown cancels the listener and all active connections. Reconnect is a new connection and registration; it does not create workspace state.

The iOS app starts the host only when the persisted browser-endpoint setting is enabled. It uses the local desktop asset server's loopback origin, generates a 32-byte token with a one-hour expiry, exposes the full WebSocket URL in Settings and Diagnostics, and stops the listener when the setting is disabled. The token rotates on every restart.

## Test coverage

`AirDeskTests/BrowserEndpointProtocolTests.swift` covers URLs, origins, validation and codecs. `AirDeskTests/BrowserEndpointHostTests.swift` covers startup, handshake rejection, token expiry, origin mismatch, registration, viewport/focus updates, duplicate/stale state, heartbeat and closure. `AirDeskTests/BrowserEndpointServiceTests.swift` covers service startup, token rotation, restart and failure state. `web/test/browser-endpoint.test.ts` covers the client/policy side.

## Pending

- Build the browser page and presentation client.
- Prove COOP/COEP and asset isolation for the single-threaded profile.
- Add reconnect UX and complete scene lifecycle handling.
- Evaluate a TLS/non-loopback transport only after the loopback baseline is qualified.

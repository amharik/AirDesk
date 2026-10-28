# AirDesk Cast Receiver

A development Web Receiver that hosts the bundled AirDesk desktop shell and accepts AirDesk input over Google Cast custom channels.

## Status

The receiver and iOS sender implement the v2 control protocol, receiver readiness, runtime state, input acknowledgements, and same-session reconnect. This has not been validated on Cast hardware, and the receiver is not registered with Google. It cannot be used as a production Cast application until it is hosted at a public HTTPS URL, registered in the Cast Developer Console, and configured in the iOS build.

The iOS app uses `SimulatedGoogleCastAdapter` when `AIRDESK_CAST_RECEIVER_APP_ID` is empty. The simulated adapter reports a ready receiver but does not render the desktop.

## Channels

- `urn:x-cast:com.airdesk.input` receives `InputEvent` JSON from the sender.
- `urn:x-cast:com.airdesk.control` carries v2 control messages in both directions.

The sender accepts only control messages for the active `sessionId` and `generation`. Malformed, oversized, mismatched, or unsupported messages are rejected or ignored.

### Sender to receiver

- `sessionStart`: session, generation, workspace, appearance, protocol versions, operation ID.
- `sessionResume`: session, generation, last acknowledged input sequence.
- `appearance`, `workspace`, `sessionEnd`, `ping`.

### Receiver to sender

- `ready`: sent only after the embedded shell reports readiness. Includes receiver version, viewport, reported persistence mode, capabilities, and the highest contiguous accepted input sequence.
- `state`, `viewport`, `ack`, `notice`, `error`, `pong`.

`ack` reports the highest contiguous shell-confirmed input sequence. The receiver does not replay pointer, button, key, or text events after reconnect.

## Packaging

Build a self-contained receiver bundle before deploying:

```sh
scripts/package-cast-receiver.sh
```

The output is `CastReceiver/dist/`:

```text
CastReceiver/dist/
  index.html
  receiver.js
  receiver.css
  desktop/
    index.html
    apps.js
    bridge.js
    desktop.js
    shell.css
    wanix-*.js
```

The packaging step copies the current desktop shell and rewrites the receiver's default shell URL to `desktop/index.html`. `CastReceiver/dist/` is disposable and gitignored.

## Hosting

For a local browser preview, serve the packaged bundle with cross-origin isolation headers:

```sh
python3 scripts/dev-desktop-server.py --root CastReceiver/dist --port 8090
```

Open:

```text
http://localhost:8090/?debug=1
```

Serving the repository root also works during development:

```sh
cd /path/to/airdesk
python3 -m http.server 8090
# open http://localhost:8090/CastReceiver/?debug=1
```

Google Cast requires HTTPS for a registered receiver. The public host must send `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` so the Wanix shell remains cross-origin isolated. Use a trusted tunnel or static host for device testing; plain `python3 -m http.server` is only suitable for local previews that do not need `SharedArrayBuffer`.

## Shell URL and bridge origin

The source receiver defaults to `../AirDesk/Resources/DesktopShell/index.html`; the packaged receiver defaults to `desktop/index.html`. Override either with the `shell` query parameter:

```text
https://receiver.example.com/CastReceiver/?shell=/desktop/index.html&session=my-session&debug=1
```

The receiver loads the shell with `host=cast`, the active session/generation, and a concrete parent origin. The shell posts messages with `window.parent.postMessage(message, parentOrigin)` and the receiver validates both `event.source` and `event.origin`. If the shell is served from a different origin, set `shellOrigin` and ensure the shell URL's origin matches:

```text
https://receiver.example.com/CastReceiver/?shell=https%3A%2F%2Fdesktop.example.com%2Findex.html&shellOrigin=https%3A%2F%2Fdesktop.example.com
```

Same-origin deployment is preferred. Do not use a wildcard target origin for control messages.

## Persistence

`ready.persistence` reports the storage mode selected by the running shell (`opfs`, `indexeddb`, `ram`, or `unknown`). It does not guarantee durability across receiver restarts, process termination, or Cast session changes. The receiver keeps an ended session's shell alive for a 30-second grace period, then clears the iframe and its in-memory state.

## Enabling the native Cast SDK

The Xcode project links the Google Cast iOS SDK 4.8.4 (dynamic) through Swift Package Manager. `SDKGoogleCastAdapter` is compiled and selected when a receiver application ID is configured.

1. Set the `AIRDESK_CAST_RECEIVER_APP_ID` build setting to the registered receiver application ID. The value flows into `AirDeskCastReceiverApplicationID` and the `_<appID>._googlecast._tcp` Bonjour service.
2. Host this receiver at the registered HTTPS URL with `CastReceiver/index.html` as the receiver entry point.
3. Rebuild and launch AirDesk on a device on the same Wi-Fi network; the simulated adapter is used only when the ID is empty.

Without a registered receiver ID, AirDesk remains on the simulated Cast adapter and the receiver works only as a browser preview.

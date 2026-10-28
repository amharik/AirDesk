# AirDesk Cast Receiver

A development Web Receiver that hosts the bundled AirDesk desktop shell and accepts AirDesk input over Google Cast custom channels.

## Status

This receiver is scaffolding. The iOS sender adapter is wired for real Cast sessions: it waits for the session, attaches input and control channels, and sends `sessionStart`, `appearance`, and `sessionEnd` control messages. The app still uses `SimulatedGoogleCastAdapter` unless the Google Cast SDK is added and a registered receiver application ID is configured. This receiver is not registered with Google and cannot be used as a production Cast application until it is hosted at a public HTTPS URL and registered in the Cast Developer Console.

## Channels

- `urn:x-cast:com.airdesk.input` receives `InputEvent` JSON from the sender.
- `urn:x-cast:com.airdesk.control` receives `sessionStart` (with `workspace`), `appearance`, and `sessionEnd` control messages.

The receiver adopts the sender's session ID from `sessionStart` or the first input event, forwards input to the embedded shell through `window.AirDeskBridge.receive`, and forwards appearance/control messages through `window.AirDeskBridge.receiveControl`.

## Hosting

Serve the repository root so the receiver can load the shell at its relative path:

```sh
cd /path/to/airdesk
python3 -m http.server 8090
```

Open:

```text
http://localhost:8090/CastReceiver/?debug=1
```

Google Cast requires HTTPS for a registered receiver. Use a trusted tunnel or static host for device testing.

## Shell URL

The default shell path is `../AirDesk/Resources/DesktopShell/index.html`. Override it with the `shell` query parameter:

```text
https://receiver.example.com/CastReceiver/?shell=/desktop/index.html&session=my-session
```

Use `debug=1` to show the receiver diagnostics panel.

## Enabling the native Cast SDK

The Xcode project links the Google Cast iOS SDK 4.8.4 (dynamic) through Swift Package Manager. `SDKGoogleCastAdapter` is compiled and selected when a receiver application ID is configured.

1. Set the `AIRDESK_CAST_RECEIVER_APP_ID` build setting to the registered receiver application ID. The value flows into `AirDeskCastReceiverApplicationID` and the `_<appID>._googlecast._tcp` Bonjour service.
2. Host this receiver at the registered HTTPS URL.
3. Rebuild and launch AirDesk on a device on the same Wi-Fi network; the simulated adapter is used only when the ID is empty.

Without a registered receiver ID, AirDesk remains on the simulated Cast adapter and the receiver works only as a browser preview.

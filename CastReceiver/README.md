# AirDesk Cast Receiver

A development Web Receiver that hosts the bundled AirDesk desktop shell and accepts AirDesk input over Google Cast custom channels.

## Status

This receiver is scaffolding. The iOS app currently uses `SimulatedGoogleCastAdapter` unless the Google Cast SDK is added and a registered receiver application ID is configured. This receiver is not registered with Google and cannot be used as a production Cast application until it is hosted at a public HTTPS URL and registered in the Cast Developer Console.

## Channels

- `urn:x-cast:com.airdesk.input` receives `InputEvent` JSON from the sender.
- `urn:x-cast:com.airdesk.control` receives control messages such as `appearance`, `sessionStart`, `sessionEnd`, and `workspace`.

The receiver forwards input to the embedded shell through `window.AirDeskBridge.receive` and control messages through `window.AirDeskBridge.receiveControl`.

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

1. Add the Google Cast iOS SDK to the Xcode project.
2. Set `AirDeskCastReceiverApplicationID` in `AirDesk/Resources/Info.plist` to the registered receiver application ID.
3. Build with the `GoogleCast` module available so `SDKGoogleCastAdapter` is compiled.
4. Host this receiver at the registered HTTPS URL.

Without those steps, AirDesk remains on the simulated Cast adapter and the receiver works only as a browser preview.

# Intercom ClientiOS

A native iOS device client for the Intercom system — plays the same *device* role as
`ClientPython` (streams a camera over WebRTC via OAuth2 device flow), so an iPhone/iPad can be
repurposed as a CCTV camera instead of needing a Raspberry Pi.

## Important: foreground-only

This app **must stay open and in the foreground** to stream. iOS suspends camera capture within
seconds of backgrounding or screen-lock, and there is no attempt here to fight that with
VoIP/PiP background-mode workarounds (unreliable for this use case, and likely to be rejected on
App Store review). Mount the device somewhere it can stay plugged in and awake — the app disables
the idle timer while active and shows a "streaming paused" banner if backgrounded.

## Toolchain: xtool, not Xcode

This project is a plain SwiftPM package (`Package.swift` + `xtool.yml`), built via
[xtool](https://github.com/xtool-org/xtool) rather than a hand-written or generated
`.xcodeproj`. This lets the app be built (and even installed to a device) from Linux/Windows, not
just macOS.

```bash
# One-time setup (installs the Darwin Swift SDK, handles Apple auth)
xtool setup

# Build
xtool dev build

# Build + install + launch on a connected device
xtool dev
# or, once built:
xtool install xtool/ClientiOS.app
xtool launch com.intercom.clientios
```

If you're on a Mac with Xcode, `xtool dev generate-xcode-project` can also produce an `.xcodeproj`
for a more familiar editing experience — the `Package.swift`/`xtool.yml` files remain the source
of truth either way.

## Architecture

- **`Sources/ClientiOSCore/`** — pure Foundation logic (models, HTTP/WebSocket clients, token
  status math). No SwiftUI/WebRTC/Security dependency, so it builds and unit-tests on plain Linux
  Swift (`swift test`) — useful since there's no iOS simulator on Linux to fall back on.
- **`Sources/ClientiOS/`** — the app target: SwiftUI views, WebRTC (camera capture, peer
  connections), Keychain-backed token storage. Only buildable for iOS (or macOS) via `xtool dev
  build` — every file is wrapped in `#if canImport(SwiftUI)` (or `canImport(UIKit)`/
  `canImport(Security)` where more specific) so `swift test` can still build the whole package
  graph on Linux without choking on Apple-only APIs.

See `DeviceClient.swift` for the orchestration loop — it's a direct port of
`ClientPython/main.py`'s `PiClient`: ensure-tokens → connect-signaling → stream, with a 30s
heartbeat and 5s retry-on-error, driven by `scenePhase` instead of SIGINT/SIGTERM.

## Setup (first run)

1. Build and install the app on a device (see above).
2. On first launch, enter your Intercom server's HTTP base URL, WebSocket base URL, and the OAuth
   device-app client ID (an admin can find this via `GET /api/v1/devices/oauth-app/` on the web
   dashboard — it's a `CLIENT_PUBLIC` OAuth client, not a secret).
3. Tap "Start Pairing" — the app will show a short user code. Approve the device from the
   Intercom web dashboard using that code (or via `auto_approve_devices` in local dev).
4. Once paired, the app connects and starts streaming its camera to any viewer who opens that
   device in the Frontend dashboard.

## Real-device verification status

Most of this project was built and verified from a Linux dev machine with no physical iPhone or
macOS host available, using `xtool dev build`/`swift test` plus live-backend wire-protocol checks
(see git history / PR description for details). Two things couldn't be verified from Linux and
needed a real device:

1. **`URLSessionWebSocketTask` at runtime.** It compiles fine on Linux, but crashes there at
   runtime ("WebSockets not supported by libcurl") — a gap in swift-corelibs-foundation's Linux
   networking backend, not a bug in this code. **Confirmed working on a real iPhone** (iOS
   15.8.3, installed via `xtool install`) — Apple's native, non-libcurl `URLSession` WebSocket
   implementation handles the signaling connection correctly.
2. **A single `RTCVideoTrack` added to multiple concurrent `RTCPeerConnection`s.** Standard
   behavior in libwebrtc's C++ core, and the reason `CameraController` doesn't need to port
   ClientPython's manual `SharedCameraSource` frame-queue fan-out. **Confirmed working**: paired
   the physical device, connected as a viewer from the Frontend dashboard, and saw live camera
   video.

Deployment note: the app was installed via `xtool install` under a free/personal Apple Developer
account, which required revoking an existing "iOS Development" certificate first (Apple limits
personal accounts to one active dev cert) — do this deliberately, since it invalidates any other
app currently signed with that cert until rebuilt. `xtool launch`'s automatic launch (which
attaches a debugserver) failed with `DebugserverClient.Error.unknown` on iOS 15.8.3, likely a
Developer Disk Image mismatch for this older OS version — launching the app manually from the
home screen works fine and is unaffected.

Still untested: multiple *simultaneous* viewers on the same device (only one viewer has been
tried so far), and telemetry log visibility in the Frontend's device list.

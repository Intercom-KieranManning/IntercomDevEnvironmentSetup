// This whole target depends on SwiftUI/WebRTC/Keychain (Apple-only), so every file in it
// is wrapped in `#if canImport(SwiftUI)`. That keeps `swift test` buildable on this Linux
// dev machine (it builds the whole package graph, including this target, even when only
// testing ClientiOSCore) — on Linux this file compiles to nothing; on iOS via `xtool` it's
// the real app.
#if canImport(SwiftUI)
import SwiftUI
import UIKit

@main
struct ClientiOSApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var deviceClient: DeviceClient
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _deviceClient = StateObject(wrappedValue: DeviceClient(settingsStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(deviceClient)
        }
        // Foreground-only by design (see README): the app is meant to run mounted/plugged in
        // like a dedicated camera, screen awake, not survive backgrounding. iOS suspends camera
        // capture within seconds of backgrounding regardless, so there's no attempt to fight
        // that with VoIP/PiP background modes — streaming just pauses, communicated to the user
        // via StatusView's banner.
        // Single-parameter onChange (not the two-parameter oldValue/newValue form, which needs
        // iOS 17+) for iOS 15 compatibility.
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                deviceClient.start()
            case .inactive, .background:
                UIApplication.shared.isIdleTimerDisabled = false
                Task { await deviceClient.stop() }
            @unknown default:
                break
            }
        }
    }
}
#endif

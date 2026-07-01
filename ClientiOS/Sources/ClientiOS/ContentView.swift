#if canImport(SwiftUI)
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var deviceClient: DeviceClient

    var body: some View {
        // NavigationView (not NavigationStack, which needs iOS 16+) for iOS 15 compatibility.
        NavigationView {
            Group {
                if !settingsStore.settings.isComplete {
                    SettingsView()
                } else if deviceClient.tokenStatus == .missing {
                    PairingView()
                } else {
                    StatusView()
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await deviceClient.refreshTokenStatus()
        }
    }
}
#endif

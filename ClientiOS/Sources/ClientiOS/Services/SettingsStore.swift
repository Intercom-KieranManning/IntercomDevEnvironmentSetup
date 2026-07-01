#if canImport(SwiftUI)
import Foundation
import SwiftUI
import ClientiOSCore

/// UserDefaults-backed persistence for `DeviceSettings` — these aren't secrets (server URLs +
/// a CLIENT_PUBLIC OAuth client id), unlike TokenStore's Keychain-backed contents.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: DeviceSettings

    private let defaults: UserDefaults
    private let key = "com.intercom.clientios.deviceSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DeviceSettings.self, from: data) {
            settings = decoded
        } else {
            settings = DeviceSettings()
        }
    }

    func update(_ newSettings: DeviceSettings) {
        settings = newSettings
        guard let data = try? JSONEncoder().encode(newSettings) else { return }
        defaults.set(data, forKey: key)
    }
}
#endif

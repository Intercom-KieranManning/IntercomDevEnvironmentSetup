#if canImport(SwiftUI)
import SwiftUI
import ClientiOSCore

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var httpBaseURLText = ""
    @State private var websocketBaseURLText = ""
    @State private var clientIDText = ""
    @State private var validationError: String?

    var body: some View {
        Form {
            Section {
                TextField("http://host:8000", text: $httpBaseURLText)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                TextField("ws://host:8000", text: $websocketBaseURLText)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Server")
            } footer: {
                Text("The Intercom backend's HTTP and WebSocket base URLs.")
            }

            Section {
                TextField("Device app client ID", text: $clientIDText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("OAuth")
            } footer: {
                Text("Ask your Intercom admin for this — it's shown on the web dashboard's device-app settings and isn't secret.")
            }

            if let validationError {
                Text(validationError).foregroundStyle(.red)
            }

            Button("Save") { save() }
        }
        .navigationTitle("Settings")
        .onAppear(perform: load)
    }

    private func load() {
        httpBaseURLText = settingsStore.settings.httpAPIBaseURL?.absoluteString ?? ""
        websocketBaseURLText = settingsStore.settings.websocketAPIBaseURL?.absoluteString ?? ""
        clientIDText = settingsStore.settings.oauthClientID ?? ""
    }

    private func save() {
        guard let httpURL = URL(string: httpBaseURLText), ["http", "https"].contains(httpURL.scheme ?? "") else {
            validationError = "Server URL must start with http:// or https://"
            return
        }
        guard let wsURL = URL(string: websocketBaseURLText), ["ws", "wss"].contains(wsURL.scheme ?? "") else {
            validationError = "WebSocket URL must start with ws:// or wss://"
            return
        }
        guard !clientIDText.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "OAuth client ID is required."
            return
        }
        validationError = nil
        settingsStore.update(DeviceSettings(
            httpAPIBaseURL: httpURL,
            websocketAPIBaseURL: wsURL,
            oauthClientID: clientIDText.trimmingCharacters(in: .whitespaces)
        ))
    }
}
#endif

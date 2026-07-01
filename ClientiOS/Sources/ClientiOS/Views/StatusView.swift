#if canImport(SwiftUI)
import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var deviceClient: DeviceClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if scenePhase != .active {
                    Label(
                        "Streaming paused — bring this app to the foreground to resume.",
                        systemImage: "pause.circle"
                    )
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                }

                CameraPreviewView(videoTrack: deviceClient.localVideoTrack)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if deviceClient.localVideoTrack == nil {
                            Text("Camera preview unavailable")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                statusCard

                Button("Re-pair Device", role: .destructive) {
                    Task { await deviceClient.clearPairing() }
                }
            }
            .padding()
        }
        .navigationTitle("Status")
        .toolbar {
            // .navigationBarTrailing (not .topBarTrailing, which needs iOS 17+) for iOS 15 compatibility.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView { SettingsView() }
                .navigationViewStyle(.stack)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(deviceClient.signalingConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(deviceClient.signalingConnected ? "Connected" : "Disconnected")
                    .bold()
            }
            Text("Active viewers: \(deviceClient.activeViewerCount)")
                .foregroundStyle(.secondary)
            if let last = deviceClient.lastSignalingMessage {
                Text("Last message: \(last)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var deviceClient: DeviceClient

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let userCode = deviceClient.pairingUserCode {
                VStack(spacing: 12) {
                    Text("Go to the Intercom web dashboard and approve this device using the code below.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text(userCode)
                        .font(.system(.largeTitle, design: .monospaced))
                        .bold()
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    ProgressView("Waiting for approval...")
                }
            } else if deviceClient.isPairing {
                ProgressView("Starting pairing...")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("This device needs to be paired with your Intercom account before it can stream.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Button("Start Pairing") {
                    Task { await deviceClient.pair() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = deviceClient.pairingError {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await deviceClient.pair() }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Pair Device")
    }
}
#endif

#if canImport(SwiftUI)
import Foundation
import SwiftUI
import WebRTC
import ClientiOSCore

enum DeviceClientError: Error {
    case notPaired
    case invalidURL
}

/// Direct analogue of ClientPython/main.py's `PiClient`: ensure-tokens -> connect-signaling ->
/// stream, with a 30s heartbeat and a 5s retry-on-error loop. Driven by `scenePhase`
/// (ClientiOSApp) instead of SIGINT/SIGTERM, since this app is foreground-only by design.
@MainActor
final class DeviceClient: ObservableObject {
    @Published private(set) var tokenStatus: TokenStatus = .missing
    @Published private(set) var pairingUserCode: String?
    @Published private(set) var pairingError: String?
    @Published private(set) var isPairing = false
    @Published private(set) var lastSignalingMessage: String?
    @Published private(set) var signalingConnected = false
    @Published private(set) var localVideoTrack: RTCVideoTrack?
    @Published private(set) var activeViewerCount = 0

    private let settingsStore: SettingsStore
    private let tokenStore = TokenStore()
    private let peerConnectionFactory = RTCPeerConnectionFactory()
    private lazy var cameraController = CameraController(factory: peerConnectionFactory)

    private var signalingClient: SignalingClient?
    private var peerConnectionCoordinator: PeerConnectionCoordinator?
    private var running = false
    private var runTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func refreshTokenStatus() async {
        tokenStatus = await tokenStore.status()
    }

    /// Runs the full RFC 8628 flow: initiate -> show user_code -> poll -> store tokens.
    /// Mirrors `PiClient.device_authorization_flow` (ClientPython/main.py).
    func pair() async {
        let settings = settingsStore.settings
        guard let httpBaseURL = settings.httpAPIBaseURL,
              let clientID = settings.oauthClientID, !clientID.isEmpty else {
            pairingError = "Complete Settings first."
            return
        }

        isPairing = true
        pairingError = nil
        pairingUserCode = nil
        defer { isPairing = false }

        let authClient = DeviceAuthorizationClient(httpAPIBaseURL: httpBaseURL)
        do {
            let auth = try await authClient.initiate(
                clientID: clientID,
                deviceType: deviceHardwareIdentifier(),
                deviceOS: deviceOSDescription()
            )
            pairingUserCode = auth.userCode

            let token = try await authClient.pollForToken(
                deviceCode: auth.deviceCode,
                clientID: clientID,
                interval: auth.interval,
                maxPollingSeconds: 5 * 60
            )

            await tokenStore.store(TokenSet(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? "",
                accessTokenExpiry: Date().addingTimeInterval(TimeInterval(token.expiresIn)).timeIntervalSince1970,
                deviceCode: auth.deviceCode
            ))
            pairingUserCode = nil
            await refreshTokenStatus()
            start()
        } catch {
            pairingUserCode = nil
            pairingError = Self.describe(error)
        }
    }

    /// Clears stored tokens so the UI routes back to pairing (e.g. after a revoked device).
    func clearPairing() async {
        await stop()
        await tokenStore.clear()
        tokenStatus = .missing
    }

    // MARK: - Lifecycle (mirrors PiClient.run() / shutdown())

    /// No-op if already running or not yet paired. Safe to call repeatedly (e.g. from both
    /// `pair()` and `scenePhase == .active`).
    func start() {
        guard !running, tokenStatus != .missing else { return }
        running = true

        heartbeatTask = Task { [weak self] in
            while let self, self.running {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard self.running else { break }
                await self.sendTelemetryIfPossible(.heartbeat)
            }
        }

        runTask = Task { [weak self] in
            while let self, self.running {
                do {
                    try await self.ensureValidTokens()
                    try await self.runSignalingLoop()
                } catch {
                    await self.sendTelemetryIfPossible(.error, message: "\(error)", level: .error)
                }
                await self.cleanupConnections()
                if self.running {
                    try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                }
            }
        }
    }

    /// Mirrors `PiClient.shutdown()`.
    func stop() async {
        guard running else { return }
        running = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        runTask?.cancel()
        runTask = nil

        await sendTelemetryIfPossible(.disconnected, message: "Client shutting down")
        await cleanupConnections()
    }

    // MARK: - Token management (mirrors PiClient.ensure_valid_tokens / refresh_flow)

    private func ensureValidTokens() async throws {
        switch await tokenStore.status() {
        case .missing:
            throw DeviceClientError.notPaired
        case .expired:
            try await refreshStoredTokens()
        case .valid:
            break
        }
    }

    private func refreshStoredTokens() async throws {
        guard let httpBaseURL = settingsStore.settings.httpAPIBaseURL,
              let clientID = settingsStore.settings.oauthClientID,
              let tokens = await tokenStore.load() else {
            throw DeviceClientError.notPaired
        }
        let authClient = DeviceAuthorizationClient(httpAPIBaseURL: httpBaseURL)
        let refreshed = try await authClient.refresh(refreshToken: tokens.refreshToken, clientID: clientID)
        await tokenStore.store(TokenSet(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? tokens.refreshToken,
            accessTokenExpiry: Date().addingTimeInterval(TimeInterval(refreshed.expiresIn)).timeIntervalSince1970,
            deviceCode: tokens.deviceCode
        ))
        await refreshTokenStatus()
    }

    // MARK: - Signaling + WebRTC (mirrors PiClient.signaling_loop)

    private func runSignalingLoop() async throws {
        guard let httpBaseURL = settingsStore.settings.httpAPIBaseURL,
              let websocketBaseURL = settingsStore.settings.websocketAPIBaseURL,
              let tokens = await tokenStore.load() else {
            throw DeviceClientError.notPaired
        }

        let turnCredentials = await TurnCredentialsClient(httpAPIBaseURL: httpBaseURL).fetch(accessToken: tokens.accessToken)

        let coordinator = PeerConnectionCoordinator(factory: peerConnectionFactory, camera: cameraController)
        coordinator.configureICEServers(
            stunURLs: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"],
            turn: turnCredentials
        )
        peerConnectionCoordinator = coordinator

        var base = websocketBaseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        guard let websocketURL = URL(string: "\(base)/ws/live_stream/\(tokens.deviceCode)/") else {
            throw DeviceClientError.invalidURL
        }

        let client = SignalingClient(url: websocketURL, accessToken: tokens.accessToken)
        signalingClient = client

        coordinator.onOutgoing = { [weak self] message in
            Task { try? await self?.signalingClient?.send(message) }
        }
        coordinator.onConnectionStateChange = { [weak self, weak coordinator] _, state in
            Task { @MainActor in
                guard let self, let coordinator else { return }
                self.activeViewerCount = coordinator.activeViewerCount
                self.localVideoTrack = self.cameraController.videoTrack
                if state == .connected {
                    await self.sendTelemetryIfPossible(.streaming)
                } else if state == .failed {
                    await self.sendTelemetryIfPossible(.error, message: "WebRTC connection failed", level: .warning)
                }
            }
        }

        await client.connect()
        signalingConnected = true
        await sendTelemetryIfPossible(.connected)
        defer { signalingConnected = false }

        for try await message in client.messages() {
            lastSignalingMessage = "\(message)"

            switch message {
            case .offer(let sdp, let viewerChannel):
                await coordinator.handleOffer(sdp: sdp, viewerChannel: viewerChannel)
                localVideoTrack = cameraController.videoTrack
                activeViewerCount = coordinator.activeViewerCount

            case .candidate(let candidate, let sdpMid, let sdpMLineIndex, let viewerChannel):
                await coordinator.handleRemoteCandidate(
                    candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, viewerChannel: viewerChannel
                )

            case .status(let event, let peerType, _, let viewerChannel):
                guard event == "peer_disconnected", peerType != "device", let viewerChannel else { break }
                await coordinator.handleViewerDisconnected(viewerChannel: viewerChannel)
                activeViewerCount = coordinator.activeViewerCount
                await sendTelemetryIfPossible(.disconnected, message: "Viewer disconnected")
                if coordinator.activeViewerCount == 0 {
                    localVideoTrack = nil
                    await sendTelemetryIfPossible(.connected)
                }

            case .answer:
                break // the device only ever sends answers, never receives one
            }
        }
    }

    private func cleanupConnections() async {
        await peerConnectionCoordinator?.teardownAll()
        peerConnectionCoordinator = nil
        localVideoTrack = nil
        activeViewerCount = 0
        await signalingClient?.close()
        signalingClient = nil
        signalingConnected = false
    }

    // MARK: - Telemetry

    private func sendTelemetryIfPossible(_ event: TelemetryEvent, message: String = "", level: TelemetryLevel = .info) async {
        guard let httpBaseURL = settingsStore.settings.httpAPIBaseURL,
              let tokens = await tokenStore.load() else { return }
        await TelemetryClient(httpAPIBaseURL: httpBaseURL).send(
            deviceCode: tokens.deviceCode, accessToken: tokens.accessToken, event: event, message: message, level: level
        )
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DeviceAuthorizationError.timedOut:
            return "Pairing timed out. Approve the device on the dashboard sooner, or try again."
        case DeviceAuthorizationError.serverError(let message):
            return message
        case DeviceAuthorizationError.invalidResponse:
            return "The server returned an unexpected response."
        default:
            return error.localizedDescription
        }
    }
}
#endif

#if canImport(UIKit)
import Foundation
import WebRTC
import ClientiOSCore

/// One `RTCPeerConnection` per viewer, keyed by the backend-assigned `viewer_channel`. Handles
/// offer -> answer, remote ICE candidates, viewer-disconnect teardown, and the failed-state
/// "reset" behavior mirrored from ClientPython's `PiClient.setup_peer_connection`.
@MainActor
final class PeerConnectionCoordinator: NSObject {
    private let factory: RTCPeerConnectionFactory
    private let camera: CameraController
    private let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var viewerChannelsByPeerConnection: [ObjectIdentifier: String] = [:]
    private var iceServers: [RTCIceServer] = []

    /// Signaling messages this coordinator wants sent back over the WebSocket (answers, ICE
    /// candidates it generates).
    var onOutgoing: ((SignalingMessage) -> Void)?
    var onConnectionStateChange: ((_ viewerChannel: String, _ state: RTCPeerConnectionState) -> Void)?

    var activeViewerCount: Int { peerConnections.count }

    init(factory: RTCPeerConnectionFactory, camera: CameraController) {
        self.factory = factory
        self.camera = camera
    }

    /// Rebuilt for each signaling connection attempt — mirrors `PiClient._build_ice_servers`
    /// (2 Google STUN servers + server-fetched TURN credentials if present). Unlike the Python
    /// client, there's no local `.env`-configured TURN fallback here; TURN is purely
    /// server-fetched on iOS.
    func configureICEServers(stunURLs: [String], turn: TurnCredentials?) {
        var servers = stunURLs.map { RTCIceServer(urlStrings: [$0]) }
        if let turn {
            servers.append(RTCIceServer(urlStrings: [turn.url], username: turn.username, credential: turn.credential))
        }
        iceServers = servers
    }

    /// Mirrors `PiClient.setup_peer_connection` + the offer-handling body of `signaling_loop`.
    func handleOffer(sdp: String, viewerChannel: String) async {
        await teardown(viewerChannel: viewerChannel, releaseCameraIfIdle: false)

        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.sdpSemantics = .unifiedPlan

        guard let peerConnection = factory.peerConnection(
            with: configuration, constraints: constraints, delegate: self
        ) else {
            return
        }
        peerConnections[viewerChannel] = peerConnection
        viewerChannelsByPeerConnection[ObjectIdentifier(peerConnection)] = viewerChannel

        do {
            let track = try await camera.start()
            peerConnection.add(track, streamIds: ["stream0"])
        } catch {
            // Camera unavailable — still answer without video, matching ClientPython's behavior
            // (it logs a warning and sends telemetry, but the answer still goes out).
        }

        do {
            try await setRemoteDescription(peerConnection, sdp: RTCSessionDescription(type: .offer, sdp: sdp))
            let answer = try await createAnswer(peerConnection)
            try await setLocalDescription(peerConnection, sdp: answer)
            onOutgoing?(.answer(sdp: answer.sdp, viewerChannel: viewerChannel))
        } catch {
            // Leave the (now-broken) peer connection in place; a connectionState change to
            // .failed (if it ever gets that far) or the next offer will replace it.
        }
    }

    func handleRemoteCandidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int32?, viewerChannel: String) async {
        guard let peerConnection = peerConnections[viewerChannel] else { return }
        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex ?? 0, sdpMid: sdpMid)
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(iceCandidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Mirrors the `status`/`peer_disconnected` handling in `signaling_loop`.
    func handleViewerDisconnected(viewerChannel: String) async {
        await teardown(viewerChannel: viewerChannel, releaseCameraIfIdle: true)
    }

    func teardownAll() async {
        for viewerChannel in Array(peerConnections.keys) {
            await teardown(viewerChannel: viewerChannel, releaseCameraIfIdle: false)
        }
        await camera.stop()
    }

    private func teardown(viewerChannel: String, releaseCameraIfIdle: Bool) async {
        guard let peerConnection = peerConnections.removeValue(forKey: viewerChannel) else { return }
        viewerChannelsByPeerConnection.removeValue(forKey: ObjectIdentifier(peerConnection))
        peerConnection.close()
        if releaseCameraIfIdle, peerConnections.isEmpty {
            await camera.stop()
        }
    }

    /// Mirrors `PiClient.setup_peer_connection`'s `connectionState == "failed"` handling: replace
    /// the peer connection with a fresh, empty one WITHOUT sending a new offer/answer. This is a
    /// no-op reset that only prevents a dead connection from lingering and erroring on stray
    /// incoming ICE candidates — it does NOT restore video for this viewer. Ported faithfully for
    /// parity with ClientPython rather than "fixed", since actually recovering would require
    /// renegotiation this port isn't attempting to add.
    private func resetFailedPeerConnection(viewerChannel: String) async {
        await teardown(viewerChannel: viewerChannel, releaseCameraIfIdle: false)

        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.sdpSemantics = .unifiedPlan
        guard let peerConnection = factory.peerConnection(
            with: configuration, constraints: constraints, delegate: self
        ) else {
            return
        }
        peerConnections[viewerChannel] = peerConnection
        viewerChannelsByPeerConnection[ObjectIdentifier(peerConnection)] = viewerChannel
    }

    // MARK: - async wrappers around WebRTC's completion-handler APIs

    private func setRemoteDescription(_ peerConnection: RTCPeerConnection, sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setLocalDescription(_ peerConnection: RTCPeerConnection, sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(sdp) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func createAnswer(_ peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnection.answer(for: constraints) { sdp, error in
                if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: error ?? CameraError.noSupportedFormat)
                }
            }
        }
    }
}

extension PeerConnectionCoordinator: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            guard let viewerChannel = viewerChannelsByPeerConnection[ObjectIdentifier(peerConnection)] else { return }
            onOutgoing?(.candidate(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int32(candidate.sdpMLineIndex),
                viewerChannel: viewerChannel
            ))
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor in
            guard let viewerChannel = viewerChannelsByPeerConnection[ObjectIdentifier(peerConnection)] else { return }
            onConnectionStateChange?(viewerChannel, newState)
            if newState == .failed {
                await resetFailedPeerConnection(viewerChannel: viewerChannel)
            }
        }
    }
}
#endif

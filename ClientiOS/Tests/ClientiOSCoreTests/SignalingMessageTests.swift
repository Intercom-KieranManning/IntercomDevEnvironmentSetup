import Foundation
import Testing
@testable import ClientiOSCore

@Suite("SignalingMessage wire protocol")
struct SignalingMessageTests {
    @Test func decodesOfferFromBackend() throws {
        let json = #"{"type":"offer","sdp":"v=0...","viewer_channel":"specific.channel.abc123"}"#
        let message = try JSONDecoder().decode(SignalingMessage.self, from: Data(json.utf8))
        #expect(message == .offer(sdp: "v=0...", viewerChannel: "specific.channel.abc123"))
    }

    @Test func encodesAnswerForBackend() throws {
        let message = SignalingMessage.answer(sdp: "v=0...", viewerChannel: "specific.channel.abc123")
        let data = try JSONEncoder().encode(message)
        let roundTripped = try JSONDecoder().decode(SignalingMessage.self, from: data)
        #expect(roundTripped == message)
    }

    @Test func candidateRoundTripsWithPrefixIntact() throws {
        // The "candidate:" prefix must never be stripped/added on either side (see
        // SignalingMessage.swift's doc comment) — confirm round-tripping preserves it verbatim.
        let raw = "candidate:842163049 1 udp 1677729535 1.2.3.4 51484 typ srflx"
        let message = SignalingMessage.candidate(
            candidate: raw, sdpMid: "0", sdpMLineIndex: 0, viewerChannel: "chan"
        )
        let data = try JSONEncoder().encode(message)
        let roundTripped = try JSONDecoder().decode(SignalingMessage.self, from: data)
        #expect(roundTripped == message)
        guard case .candidate(let candidate, _, _, _) = roundTripped else {
            Issue.record("expected .candidate")
            return
        }
        #expect(candidate.hasPrefix("candidate:"))
    }

    @Test func candidateToleratesNullSdpMidAndIndex() throws {
        let json = #"{"type":"candidate","candidate":"candidate:foo","sdpMid":null,"sdpMLineIndex":null,"viewer_channel":"chan"}"#
        let message = try JSONDecoder().decode(SignalingMessage.self, from: Data(json.utf8))
        #expect(message == .candidate(candidate: "candidate:foo", sdpMid: nil, sdpMLineIndex: nil, viewerChannel: "chan"))
    }

    @Test func decodesViewerDisconnectedStatus() throws {
        // Matches live_stream/consumers.py's disconnect() for a non-device (viewer) peer.
        let json = #"""
        {"type":"status","event":"peer_disconnected","peer_type":"viewer","device_id":"dev-1","viewer_channel":"chan-1"}
        """#
        let message = try JSONDecoder().decode(SignalingMessage.self, from: Data(json.utf8))
        #expect(message == .status(event: "peer_disconnected", peerType: "viewer", deviceID: "dev-1", viewerChannel: "chan-1"))
    }

    @Test func decodesDeviceConnectedStatusWithoutViewerChannel() throws {
        // Matches consumers.py's connect() status_update, which never includes viewer_channel.
        let json = #"{"type":"status","event":"peer_connected","peer_type":"device","device_id":"dev-1"}"#
        let message = try JSONDecoder().decode(SignalingMessage.self, from: Data(json.utf8))
        #expect(message == .status(event: "peer_connected", peerType: "device", deviceID: "dev-1", viewerChannel: nil))
    }

    @Test func unknownTypeThrows() {
        let json = #"{"type":"bogus"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SignalingMessage.self, from: Data(json.utf8))
        }
    }
}

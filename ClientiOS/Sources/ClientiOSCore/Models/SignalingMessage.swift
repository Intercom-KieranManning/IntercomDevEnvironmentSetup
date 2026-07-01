import Foundation

/// Mirrors the flat, `type`-discriminated JSON messages relayed by
/// APIServer/live_stream/consumers.py `LiveStreamSignalingConsumer`. `viewerChannel` is an opaque
/// backend-assigned channel name (a Django Channels channel name) — always echoed back verbatim,
/// never parsed or constructed by the client.
public enum SignalingMessage: Equatable, Sendable {
    /// Backend -> device only.
    case offer(sdp: String, viewerChannel: String)
    /// Device -> backend only.
    case answer(sdp: String, viewerChannel: String)
    /// Bidirectional. `candidate` is the full ICE candidate string INCLUDING the "candidate:"
    /// prefix — pass through verbatim in both directions, no stripping (unlike ClientPython's
    /// aiortc-specific workaround; iOS's native RTCIceCandidate.sdp is already prefixed like the
    /// browser's).
    case candidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int32?, viewerChannel: String)
    /// Server-generated presence notification. `viewerChannel` is only present on a viewer's own
    /// disconnect event (device disconnects never carry one).
    case status(event: String, peerType: String, deviceID: String, viewerChannel: String?)
}

extension SignalingMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, sdp, candidate, sdpMid, sdpMLineIndex, event
        case viewerChannel = "viewer_channel"
        case peerType = "peer_type"
        case deviceID = "device_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "offer":
            self = .offer(
                sdp: try container.decode(String.self, forKey: .sdp),
                viewerChannel: try container.decode(String.self, forKey: .viewerChannel)
            )
        case "answer":
            self = .answer(
                sdp: try container.decode(String.self, forKey: .sdp),
                viewerChannel: try container.decode(String.self, forKey: .viewerChannel)
            )
        case "candidate":
            self = .candidate(
                candidate: try container.decode(String.self, forKey: .candidate),
                sdpMid: try container.decodeIfPresent(String.self, forKey: .sdpMid),
                sdpMLineIndex: try container.decodeIfPresent(Int32.self, forKey: .sdpMLineIndex),
                viewerChannel: try container.decode(String.self, forKey: .viewerChannel)
            )
        case "status":
            self = .status(
                event: try container.decode(String.self, forKey: .event),
                peerType: try container.decode(String.self, forKey: .peerType),
                deviceID: try container.decode(String.self, forKey: .deviceID),
                viewerChannel: try container.decodeIfPresent(String.self, forKey: .viewerChannel)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown signaling message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .offer(let sdp, let viewerChannel):
            try container.encode("offer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
            try container.encode(viewerChannel, forKey: .viewerChannel)
        case .answer(let sdp, let viewerChannel):
            try container.encode("answer", forKey: .type)
            try container.encode(sdp, forKey: .sdp)
            try container.encode(viewerChannel, forKey: .viewerChannel)
        case .candidate(let candidate, let sdpMid, let sdpMLineIndex, let viewerChannel):
            try container.encode("candidate", forKey: .type)
            try container.encode(candidate, forKey: .candidate)
            try container.encodeIfPresent(sdpMid, forKey: .sdpMid)
            try container.encodeIfPresent(sdpMLineIndex, forKey: .sdpMLineIndex)
            try container.encode(viewerChannel, forKey: .viewerChannel)
        case .status(let event, let peerType, let deviceID, let viewerChannel):
            try container.encode("status", forKey: .type)
            try container.encode(event, forKey: .event)
            try container.encode(peerType, forKey: .peerType)
            try container.encode(deviceID, forKey: .deviceID)
            try container.encodeIfPresent(viewerChannel, forKey: .viewerChannel)
        }
    }
}

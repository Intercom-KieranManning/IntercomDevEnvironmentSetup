import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SignalingClientError: Error, Sendable {
    case notConnected
}

/// Wraps the single signaling WebSocket connection to
/// `{websocketAPIBaseURL}/ws/live_stream/{deviceCode}/`, authenticated via a Bearer header on the
/// upgrade request (validated server-side by
/// APIServer/authentication/middleware.py `WebsocketJwtTokenAuthMiddleware`).
public actor SignalingClient {
    private let url: URL
    private let accessToken: String
    private let urlSession: URLSession
    private var task: URLSessionWebSocketTask?

    public init(url: URL, accessToken: String, urlSession: URLSession = .shared) {
        self.url = url
        self.accessToken = accessToken
        self.urlSession = urlSession
    }

    public func connect() {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let task = urlSession.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    public func send(_ message: SignalingMessage) async throws {
        guard let task else { throw SignalingClientError.notConnected }
        let data = try JSONEncoder().encode(message)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    public func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receiveOne() async throws -> SignalingMessage {
        guard let task else { throw SignalingClientError.notConnected }
        let frame = try await task.receive()
        let data: Data
        switch frame {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: throw SignalingClientError.notConnected
        }
        return try JSONDecoder().decode(SignalingMessage.self, from: data)
    }

    /// One decoded `SignalingMessage` per inbound WS frame — mirrors the one-JSON-object-per-line
    /// framing `websockets`/Channels use in ClientPython's `signaling_loop`.
    public nonisolated func messages() -> AsyncThrowingStream<SignalingMessage, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    while true {
                        let message = try await self.receiveOne()
                        continuation.yield(message)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in streamTask.cancel() }
        }
    }
}

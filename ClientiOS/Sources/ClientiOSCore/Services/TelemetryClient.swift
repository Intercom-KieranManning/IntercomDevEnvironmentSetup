import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ports ClientPython/intercomclient/telemetry.py — fire-and-forget, never throws, so a telemetry
/// failure can never disrupt the signaling loop.
public struct TelemetryClient: Sendable {
    public var httpAPIBaseURL: URL
    public var transport: HTTPTransport

    public init(httpAPIBaseURL: URL, transport: @escaping HTTPTransport = LiveHTTPTransport.shared) {
        self.httpAPIBaseURL = httpAPIBaseURL
        self.transport = transport
    }

    public func send(
        deviceCode: String,
        accessToken: String,
        event: TelemetryEvent,
        message: String = "",
        level: TelemetryLevel = .info
    ) async {
        do {
            var request = URLRequest(
                url: httpAPIBaseURL.appendingAPIPath("api/v1/devices/\(deviceCode)/telemetry/")
            )
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode([
                "event": event.rawValue,
                "message": message,
                "level": level.rawValue,
            ])
            _ = try await transport(request)
        } catch {
            // Swallowed intentionally — mirrors telemetry.py's bare `except Exception`.
        }
    }
}

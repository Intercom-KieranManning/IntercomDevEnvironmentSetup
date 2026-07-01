import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ports ClientPython/intercomclient/turn.py — swallows all failures, returning nil (TURN is an
/// optional ICE-server addition, never a hard requirement).
public struct TurnCredentialsClient: Sendable {
    public var httpAPIBaseURL: URL
    public var transport: HTTPTransport

    public init(httpAPIBaseURL: URL, transport: @escaping HTTPTransport = LiveHTTPTransport.shared) {
        self.httpAPIBaseURL = httpAPIBaseURL
        self.transport = transport
    }

    public func fetch(accessToken: String) async -> TurnCredentials? {
        do {
            var request = URLRequest(url: httpAPIBaseURL.appendingAPIPath("api/v1/users/turn-credentials/"))
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            let (data, _) = try await transport(request)
            return try JSONDecoder().decode(TurnCredentialsResponse.self, from: data).turnCredentials
        } catch {
            return nil
        }
    }
}

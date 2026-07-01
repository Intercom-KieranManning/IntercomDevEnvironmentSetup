import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ports ClientPython/intercomclient/device_authorization.py exactly.
public struct DeviceAuthorizationClient: Sendable {
    public var httpAPIBaseURL: URL
    public var transport: HTTPTransport

    public init(httpAPIBaseURL: URL, transport: @escaping HTTPTransport = LiveHTTPTransport.shared) {
        self.httpAPIBaseURL = httpAPIBaseURL
        self.transport = transport
    }

    public func initiate(clientID: String, deviceType: String, deviceOS: String) async throws -> DeviceAuthorizationResponse {
        var request = URLRequest(url: httpAPIBaseURL.appendingAPIPath("oauth/device-authorization/"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncode([
            "client_id": clientID,
            "device_type": deviceType,
            "device_os": deviceOS,
            // Literal string ClientPython actually sends — its Config.oauth_scope field
            // ("openid email profile") exists but is unused; mirror the real behavior.
            "scope": "profile email",
        ])
        let (data, response) = try await transport(request)
        try Self.validateSuccess(response: response, data: data)
        return try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: data)
    }

    /// Sleeps `interval` seconds before each poll attempt, including the first — matches
    /// ClientPython's `poll_for_token`, which never polls immediately on entry.
    public func pollForToken(
        deviceCode: String,
        clientID: String,
        interval: Int,
        maxPollingSeconds: Int
    ) async throws -> TokenResponse {
        let deadline = Date().addingTimeInterval(TimeInterval(maxPollingSeconds))
        while true {
            if Date() > deadline {
                throw DeviceAuthorizationError.timedOut
            }
            try await Task.sleep(nanoseconds: UInt64(max(interval, 0)) * 1_000_000_000)

            var request = URLRequest(url: httpAPIBaseURL.appendingAPIPath("oauth/token/"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formURLEncode([
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": deviceCode,
                "client_id": clientID,
            ])
            let (data, _) = try await transport(request)

            if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                if errorResponse.error == "authorization_pending" {
                    continue
                }
                throw DeviceAuthorizationError.serverError(errorResponse.errorDescription ?? errorResponse.error)
            }
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        }
    }

    public func refresh(refreshToken: String, clientID: String) async throws -> TokenResponse {
        var request = URLRequest(url: httpAPIBaseURL.appendingAPIPath("oauth/token/"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncode([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ])
        let (data, response) = try await transport(request)
        try Self.validateSuccess(response: response, data: data)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func validateSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw DeviceAuthorizationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw DeviceAuthorizationError.serverError(err.errorDescription ?? err.error)
            }
            throw DeviceAuthorizationError.serverError("HTTP \(http.statusCode)")
        }
    }
}

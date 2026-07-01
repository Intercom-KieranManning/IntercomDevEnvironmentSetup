import Foundation

/// RFC 8628 device authorization response. `verificationURI` is currently always "" server-side
/// (see APIServer/client_devices/views.py DeviceAuthorizationView) — the admin approves devices
/// from the web dashboard, not a URL the device itself surfaces.
public struct DeviceAuthorizationResponse: Decodable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct TokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

public enum DeviceAuthorizationError: Error, Equatable, Sendable {
    case timedOut
    case serverError(String)
    case invalidResponse
}

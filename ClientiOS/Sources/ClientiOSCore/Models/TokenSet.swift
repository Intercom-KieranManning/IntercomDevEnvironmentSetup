import Foundation

/// Mirrors the shape ClientPython's `token_store.py` persists (access/refresh/expiry/device_code),
/// just stored in the Keychain instead of a 0600 JSON file.
public struct TokenSet: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    /// Epoch seconds, matching `token_store.py`'s "expiry_time".
    public var accessTokenExpiry: TimeInterval
    public var deviceCode: String

    public init(accessToken: String, refreshToken: String, accessTokenExpiry: TimeInterval, deviceCode: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiry = accessTokenExpiry
        self.deviceCode = deviceCode
    }
}

/// Mirrors `PiClient.check_token_status` in ClientPython/main.py.
public enum TokenStatus: Equatable, Sendable {
    case valid
    case expired
    case missing

    public static func compute(from tokens: TokenSet?, now: Date = Date()) -> TokenStatus {
        guard let tokens else { return .missing }
        return tokens.accessTokenExpiry < now.timeIntervalSince1970 ? .expired : .valid
    }
}

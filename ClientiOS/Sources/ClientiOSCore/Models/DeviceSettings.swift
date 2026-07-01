import Foundation

/// Mirrors ClientPython's `Config` (http_api_base_url, websocket_api_base_url, oauth_client_id),
/// sourced from a Settings screen + UserDefaults instead of env vars since none of these are secrets.
public struct DeviceSettings: Codable, Equatable, Sendable {
    public var httpAPIBaseURL: URL?
    public var websocketAPIBaseURL: URL?
    public var oauthClientID: String?

    public init(httpAPIBaseURL: URL? = nil, websocketAPIBaseURL: URL? = nil, oauthClientID: String? = nil) {
        self.httpAPIBaseURL = httpAPIBaseURL
        self.websocketAPIBaseURL = websocketAPIBaseURL
        self.oauthClientID = oauthClientID
    }

    public var isComplete: Bool {
        httpAPIBaseURL != nil && websocketAPIBaseURL != nil && !(oauthClientID ?? "").isEmpty
    }
}

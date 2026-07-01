import Foundation

/// `application/x-www-form-urlencoded` body encoding for the OAuth endpoints, which (per
/// APIServer/client_devices/views.py `DeviceAuthorizationView`) expect form-encoded POST bodies,
/// not JSON.
func formURLEncode(_ params: [String: String]) -> Data {
    let encoded = params.map { key, value in
        "\(key.addingPercentEncoding(withAllowedCharacters: .formValueAllowed) ?? key)=" +
        "\(value.addingPercentEncoding(withAllowedCharacters: .formValueAllowed) ?? value)"
    }.joined(separator: "&")
    return Data(encoded.utf8)
}

private extension CharacterSet {
    static let formValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return allowed
    }()
}

extension URL {
    /// `appendingPathComponent` silently normalizes away a trailing slash on the appended
    /// component (confirmed empirically — see TelemetryAndTurnClientTests). Django's
    /// `APPEND_SLASH` redirect-on-missing-slash behavior loses the POST body on redirect, so
    /// every API path here needs its trailing slash preserved exactly.
    func appendingAPIPath(_ path: String) -> URL {
        var base = absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        let suffix = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: base + suffix) else {
            preconditionFailure("Invalid API path: \(path)")
        }
        return url
    }
}

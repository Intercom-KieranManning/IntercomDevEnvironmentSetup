import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Injectable HTTP transport so the OAuth/telemetry/TURN clients can be unit tested with a plain
/// closure instead of relying on `URLProtocol` interception, which isn't reliably supported by
/// swift-corelibs-foundation's `URLSession` on Linux (confirmed empirically: canned responses
/// registered via a `URLProtocol` subclass never got invoked here, failing with
/// `NSURLErrorDomain -1100`).
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public enum LiveHTTPTransport {
    public static let shared: HTTPTransport = { request in
        try await URLSession.shared.data(for: request)
    }
}

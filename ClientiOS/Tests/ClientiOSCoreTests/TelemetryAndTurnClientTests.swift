import Foundation
import Testing
@testable import ClientiOSCore

@Suite("TelemetryClient")
struct TelemetryClientTests {
    @Test func sendPostsExpectedEventPayloadAndAuthHeader() async throws {
        let stub = StubbedResponses([.init(statusCode: 200, body: Data(#"{"status":"ok"}"#.utf8))])
        let client = TelemetryClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        await client.send(deviceCode: "dev-1", accessToken: "tok-1", event: .streaming, message: "started", level: .info)

        let requests = await stub.requests
        #expect(requests.count == 1)
        // NOTE: check absoluteString, not `.url?.path` — Foundation's `URL.path` accessor
        // normalizes away a trailing slash even though it IS present on the wire (confirmed via
        // appendingAPIPath's doc comment / FormEncoding.swift).
        #expect(requests[0].url?.absoluteString == "http://backend:8000/api/v1/devices/dev-1/telemetry/")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        let payload = try JSONSerialization.jsonObject(with: requests[0].httpBody ?? Data()) as? [String: String]
        #expect(payload?["event"] == "streaming")
        #expect(payload?["message"] == "started")
        #expect(payload?["level"] == "INFO")
    }

    @Test func sendNeverThrowsOnTransportFailure() async throws {
        struct Boom: Error {}
        let client = TelemetryClient(httpAPIBaseURL: URL(string: "http://backend:8000")!) { _ in throw Boom() }
        // Must not throw/crash — telemetry failures are always swallowed.
        await client.send(deviceCode: "dev-1", accessToken: "tok-1", event: .error, message: "boom", level: .error)
    }
}

@Suite("TurnCredentialsClient")
struct TurnCredentialsClientTests {
    @Test func fetchReturnsCredentialsWhenConfigured() async throws {
        let stub = StubbedResponses([.init(statusCode: 200, body: Data(#"""
        {"turn_credentials": {"url": "turn:host:3478", "username": "1234:intercom", "credential": "abc"}}
        """#.utf8))])
        let client = TurnCredentialsClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        let creds = await client.fetch(accessToken: "tok-1")
        #expect(creds?.url == "turn:host:3478")
        #expect(creds?.username == "1234:intercom")
    }

    @Test func fetchReturnsNilWhenTurnNotConfigured() async throws {
        let stub = StubbedResponses([.init(statusCode: 200, body: Data(#"{"turn_credentials": null}"#.utf8))])
        let client = TurnCredentialsClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        let creds = await client.fetch(accessToken: "tok-1")
        #expect(creds == nil)
    }

    @Test func fetchReturnsNilOnTransportFailure() async throws {
        struct Boom: Error {}
        let client = TurnCredentialsClient(httpAPIBaseURL: URL(string: "http://backend:8000")!) { _ in throw Boom() }
        let creds = await client.fetch(accessToken: "tok-1")
        #expect(creds == nil)
    }
}

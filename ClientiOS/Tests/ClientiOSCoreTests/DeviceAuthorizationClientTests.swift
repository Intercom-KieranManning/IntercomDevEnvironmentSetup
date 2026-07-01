import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ClientiOSCore

/// A queue of canned (status, body) responses returned in order by a stubbed `HTTPTransport`,
/// recording every request it was asked to make.
actor StubbedResponses {
    struct Canned { let statusCode: Int; let body: Data }

    private var queue: [Canned]
    private(set) var requests: [URLRequest] = []

    init(_ queue: [Canned]) { self.queue = queue }

    func transport(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queue.isEmpty else { fatalError("StubbedResponses exhausted") }
        let next = queue.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.statusCode, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (next.body, response)
    }
}

@Suite("DeviceAuthorizationClient")
struct DeviceAuthorizationClientTests {
    @Test func initiateSendsFormEncodedBodyWithExactScope() async throws {
        let stub = StubbedResponses([
            .init(statusCode: 200, body: Data(#"""
            {"device_code":"dc-1","user_code":"ABCD-EFGH","verification_uri":"","expires_in":600,"interval":5}
            """#.utf8)),
        ])
        let client = DeviceAuthorizationClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        let response = try await client.initiate(clientID: "client-1", deviceType: "iPhone16,2", deviceOS: "iOS 17.0")

        #expect(response.deviceCode == "dc-1")
        #expect(response.userCode == "ABCD-EFGH")
        #expect(response.interval == 5)

        let requests = await stub.requests
        let body = String(decoding: requests[0].httpBody ?? Data(), as: UTF8.self)
        // Mirrors ClientPython's literal "profile email" scope, not its unused oauth_scope config field.
        #expect(body.contains("scope=profile%20email"))
        #expect(body.contains("client_id=client-1"))
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test func pollForTokenRetriesOnAuthorizationPendingThenSucceeds() async throws {
        let stub = StubbedResponses([
            .init(statusCode: 400, body: Data(#"{"error":"authorization_pending"}"#.utf8)),
            .init(statusCode: 400, body: Data(#"{"error":"authorization_pending"}"#.utf8)),
            .init(statusCode: 200, body: Data(#"""
            {"access_token":"at-1","refresh_token":"rt-1","expires_in":3600,"token_type":"Bearer"}
            """#.utf8)),
        ])
        let client = DeviceAuthorizationClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        let token = try await client.pollForToken(
            deviceCode: "dc-1", clientID: "client-1", interval: 0, maxPollingSeconds: 5
        )

        #expect(token.accessToken == "at-1")
        #expect(token.refreshToken == "rt-1")
        let requestCount = await stub.requests.count
        #expect(requestCount == 3)
    }

    @Test func pollForTokenThrowsOnNonPendingError() async throws {
        let stub = StubbedResponses([
            .init(statusCode: 400, body: Data(#"{"error":"expired_token","error_description":"device code expired"}"#.utf8)),
        ])
        let client = DeviceAuthorizationClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        await #expect(throws: DeviceAuthorizationError.self) {
            try await client.pollForToken(deviceCode: "dc-1", clientID: "client-1", interval: 0, maxPollingSeconds: 5)
        }
    }

    @Test func pollForTokenTimesOutWhenDeadlinePasses() async throws {
        let stub = StubbedResponses(
            Array(repeating: .init(statusCode: 400, body: Data(#"{"error":"authorization_pending"}"#.utf8)), count: 10)
        )
        let client = DeviceAuthorizationClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        await #expect(throws: DeviceAuthorizationError.self) {
            try await client.pollForToken(deviceCode: "dc-1", clientID: "client-1", interval: 1, maxPollingSeconds: 0)
        }
    }

    @Test func refreshPostsRefreshTokenGrant() async throws {
        let stub = StubbedResponses([
            .init(statusCode: 200, body: Data(#"""
            {"access_token":"at-2","refresh_token":"rt-2","expires_in":3600,"token_type":"Bearer"}
            """#.utf8)),
        ])
        let client = DeviceAuthorizationClient(
            httpAPIBaseURL: URL(string: "http://backend:8000")!,
            transport: { try await stub.transport($0) }
        )

        let token = try await client.refresh(refreshToken: "rt-old", clientID: "client-1")
        #expect(token.accessToken == "at-2")

        let requests = await stub.requests
        let body = String(decoding: requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=rt-old"))
    }
}

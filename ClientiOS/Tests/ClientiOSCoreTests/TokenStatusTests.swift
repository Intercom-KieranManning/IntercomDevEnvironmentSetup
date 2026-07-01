import Foundation
import Testing
@testable import ClientiOSCore

@Suite("TokenStatus")
struct TokenStatusTests {
    @Test func missingWhenNoTokens() {
        #expect(TokenStatus.compute(from: nil) == .missing)
    }

    @Test func validWhenExpiryInFuture() {
        let tokens = TokenSet(
            accessToken: "a", refreshToken: "r",
            accessTokenExpiry: Date().addingTimeInterval(3600).timeIntervalSince1970,
            deviceCode: "dev-1"
        )
        #expect(TokenStatus.compute(from: tokens) == .valid)
    }

    @Test func expiredWhenExpiryInPast() {
        let tokens = TokenSet(
            accessToken: "a", refreshToken: "r",
            accessTokenExpiry: Date().addingTimeInterval(-3600).timeIntervalSince1970,
            deviceCode: "dev-1"
        )
        #expect(TokenStatus.compute(from: tokens) == .expired)
    }
}

@Suite("DeviceSettings")
struct DeviceSettingsTests {
    @Test func incompleteWhenAnyFieldMissing() {
        #expect(DeviceSettings().isComplete == false)
        #expect(DeviceSettings(httpAPIBaseURL: URL(string: "http://x")).isComplete == false)
    }

    @Test func completeWhenAllFieldsPresent() {
        let settings = DeviceSettings(
            httpAPIBaseURL: URL(string: "http://x"),
            websocketAPIBaseURL: URL(string: "ws://x"),
            oauthClientID: "client-1"
        )
        #expect(settings.isComplete)
    }
}

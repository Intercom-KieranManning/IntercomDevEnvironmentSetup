// Keychain-backed token persistence — the equivalent-security replacement for ClientPython's
// 0600 tokens.json (see token_store.py). Requires the Security framework, so (like the rest of
// this target) it's guarded so `swift test` on Linux can still build the package graph; real
// coverage comes from `TokenStatus.compute` in ClientiOSCore (platform-independent) plus live
// testing on a device.
#if canImport(Security)
import Foundation
import Security
import ClientiOSCore

public actor TokenStore {
    private let service: String
    private let account = "oauth-tokens"

    public init(service: String = (Bundle.main.bundleIdentifier ?? "ClientiOS") + ".tokens") {
        self.service = service
    }

    public func load() -> TokenSet? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    public func store(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }

        if load() != nil {
            let update: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
        } else {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    public func status(now: Date = Date()) -> TokenStatus {
        TokenStatus.compute(from: load(), now: now)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif

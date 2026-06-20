import Foundation
import Security

/// A `TokenStore` backed by the iOS/macOS keychain (`Security` framework).
///
/// The access + refresh token pair is stored as a single JSON blob under one
/// generic-password item keyed by `service` + `account`, so save/load/clear are
/// atomic. The `service` is configurable so tests can isolate themselves with a
/// unique service name and never touch the production item.
public struct KeychainTokenStore: TokenStore {

    /// Failures surfaced by the underlying `SecItem*` calls.
    public enum KeychainError: Error, Equatable, Sendable {
        case unexpectedStatus(OSStatus)
        case decoding
    }

    private let service: String
    private let account: String

    public init(service: String = "com.notova.app.auth", account: String = "tokens") {
        self.service = service
        self.account = account
    }

    public func save(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        // Delete-then-add keeps the operation idempotent and avoids the subtle
        // attribute differences between SecItemAdd and SecItemUpdate.
        SecItemDelete(baseQuery() as CFDictionary)

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func load() throws -> AuthTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.decoding }
            do {
                return try JSONDecoder().decode(AuthTokens.self, from: data)
            } catch {
                throw KeychainError.decoding
            }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// A simple in-memory `TokenStore` for tests and previews. Not persistent and
/// not secure — never use in production.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: AuthTokens?

    public init(tokens: AuthTokens? = nil) {
        self.tokens = tokens
    }

    public func save(_ tokens: AuthTokens) throws {
        lock.withLock { self.tokens = tokens }
    }

    public func load() throws -> AuthTokens? {
        lock.withLock { tokens }
    }

    public func clear() throws {
        lock.withLock { tokens = nil }
    }
}

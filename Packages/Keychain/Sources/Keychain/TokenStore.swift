import Foundation

/// The pair of tokens issued by the Notova backend on register/login.
public struct AuthTokens: Sendable, Equatable, Codable {
    public let accessToken: String
    public let refreshToken: String

    public init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

/// Abstraction over secure token storage so view models can be unit-tested
/// against an in-memory double instead of the real system keychain.
public protocol TokenStore: Sendable {
    /// Persists the token pair, replacing any existing value. Throws on failure.
    func save(_ tokens: AuthTokens) throws
    /// Returns the stored token pair, or `nil` when nothing is stored.
    func load() throws -> AuthTokens?
    /// Removes any stored tokens. A no-op when nothing is stored.
    func clear() throws
}

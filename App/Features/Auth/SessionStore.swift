import Foundation
import SwiftUI
import NotovaCore
import Integrations
import Keychain

/// Owns the authentication lifecycle for the app: which screen the root shows
/// (`SignIn` vs the main `TabView`), the keychain-backed token pair, and the
/// access token applied to the shared backend client.
///
/// `backend` is typed as `AuthBackend` so unit tests can inject a fake; in
/// production it is the real `NotovaBackendClient` actor from `AppContainer`.
@Observable
@MainActor
final class SessionStore {
    enum Phase: Equatable {
        /// Launch-time: deciding whether a stored token exists.
        case loading
        case signedOut
        case signedIn(email: String)
    }

    private(set) var phase: Phase = .loading
    /// The signed-in user's email, when known.
    private(set) var userEmail: String?

    let backend: AuthBackend
    private let tokenStore: TokenStore

    /// Cached in memory so the 401-refresh path doesn't re-read the keychain on
    /// the hot path; always kept in sync with what's persisted.
    private var tokens: AuthTokens?

    init(backend: AuthBackend, tokenStore: TokenStore) {
        self.backend = backend
        self.tokenStore = tokenStore
    }

    // MARK: - Launch

    /// On launch: if a token pair is stored, apply the access token to the
    /// client and go straight to the signed-in UI; otherwise show SignIn.
    func restore() async {
        let stored = (try? tokenStore.load()) ?? nil
        guard let stored else {
            phase = .signedOut
            return
        }
        tokens = stored
        await backend.setAuthToken(stored.accessToken)
        // Best-effort identity fetch — but never block sign-in on it. A failure
        // that isn't a hard 401 (e.g. offline) keeps the user signed in.
        do {
            let user = try await backend.me()
            userEmail = user.email
            phase = .signedIn(email: user.email)
        } catch NotovaBackendClient.BackendError.unauthorized {
            // Access token rejected — try a single refresh, else sign out.
            if await refreshAccessToken() {
                let email = (try? await backend.me())?.email ?? ""
                userEmail = email
                phase = .signedIn(email: email)
            } else {
                await signOut()
            }
        } catch {
            // Non-auth failure: trust the stored token and proceed.
            phase = .signedIn(email: "")
        }
    }

    // MARK: - Sign in / out

    func completeSignIn(with response: NotovaBackendClient.AuthResponse) async throws {
        let pair = AuthTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
        try tokenStore.save(pair)
        tokens = pair
        await backend.setAuthToken(pair.accessToken)
        userEmail = response.user.email
        phase = .signedIn(email: response.user.email)
    }

    /// UI-test seam: synchronously place the session in the signed-in phase so
    /// XCUITests land on the main TabView without a live backend or keychain.
    func bootstrapSignedInForUITests(email: String) {
        userEmail = email
        phase = .signedIn(email: email)
    }

    func signOut() async {
        try? tokenStore.clear()
        tokens = nil
        userEmail = nil
        await backend.setAuthToken(nil)
        phase = .signedOut
    }

    // MARK: - 401 handling

    /// Runs an authorized backend call, transparently refreshing the access
    /// token once on a 401 and retrying. If refresh also fails, signs out and
    /// rethrows `.unauthorized`.
    func withAuthRetry<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch NotovaBackendClient.BackendError.unauthorized {
            guard await refreshAccessToken() else {
                await signOut()
                throw NotovaBackendClient.BackendError.unauthorized
            }
            do {
                return try await operation()
            } catch NotovaBackendClient.BackendError.unauthorized {
                await signOut()
                throw NotovaBackendClient.BackendError.unauthorized
            }
        }
    }

    /// Exchanges the stored refresh token for a fresh access token. Returns
    /// `false` (without mutating phase) when there's no refresh token or the
    /// exchange fails.
    @discardableResult
    private func refreshAccessToken() async -> Bool {
        guard let refreshToken = tokens?.refreshToken else { return false }
        do {
            let response = try await backend.refresh(refreshToken: refreshToken)
            let updated = AuthTokens(accessToken: response.accessToken, refreshToken: refreshToken)
            try? tokenStore.save(updated)
            tokens = updated
            await backend.setAuthToken(response.accessToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Error formatting

    /// Maps a backend error to a short, user-facing message.
    static func message(for error: Error) -> String {
        switch error {
        case NotovaBackendClient.BackendError.unauthorized:
            return "Incorrect email or password."
        case let NotovaBackendClient.BackendError.http(status) where status == 409:
            return "An account with that email already exists."
        case let NotovaBackendClient.BackendError.http(status) where status == 400:
            return "Please check your email and password and try again."
        case let NotovaBackendClient.BackendError.http(status):
            return "Something went wrong (HTTP \(status)). Please try again."
        case NotovaBackendClient.BackendError.decoding:
            return "Unexpected response from the server."
        default:
            return "Network error. Check your connection and try again."
        }
    }
}

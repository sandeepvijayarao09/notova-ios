import Foundation
import SwiftUI
import NotovaCore
import Integrations
import Keychain

/// Drives the SignIn screen: collects email + password, calls login/register on
/// the backend, persists the returned tokens in the keychain, sets the access
/// token on the client, and flips the shared `SessionStore` to `.signedIn`.
@Observable
@MainActor
final class AuthViewModel {
    enum Field: String { case login, register }

    var email: String = ""
    var password: String = ""
    /// User-visible error from the last attempt, or `nil`.
    var errorMessage: String?
    /// True while a network request is in flight (disables the form).
    var isBusy: Bool = false

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    /// Both Sign In and Create Account are valid only with non-empty fields.
    var canSubmit: Bool {
        !isBusy && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    func signIn() async {
        await submit { backend in
            try await backend.login(email: self.trimmedEmail, password: self.password)
        }
    }

    func createAccount() async {
        await submit { backend in
            try await backend.register(email: self.trimmedEmail, password: self.password)
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit(
        _ call: @escaping (AuthBackend) async throws -> NotovaBackendClient.AuthResponse
    ) async {
        guard canSubmit else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await call(session.backend)
            try await session.completeSignIn(with: response)
            password = ""
        } catch {
            errorMessage = SessionStore.message(for: error)
        }
    }
}

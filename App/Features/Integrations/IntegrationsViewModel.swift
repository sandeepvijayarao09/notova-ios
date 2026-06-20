import Foundation
import SwiftUI
import NotovaCore
import Integrations

/// Drives the Integrations screen: lists providers with their connected status,
/// starts the OAuth connect flow, parses the `notova://oauth/<provider>` callback,
/// and disconnects.
///
/// The OAuth web step is injected as `authorize` so the view model is fully
/// testable without `ASWebAuthenticationSession`. In production the view passes
/// a closure that drives an `ASWebAuthenticationSession`.
@Observable
@MainActor
final class IntegrationsViewModel {

    /// One row in the providers list.
    struct Row: Identifiable, Equatable {
        let provider: String
        let connected: Bool
        var id: String { provider }
        var displayName: String { provider.capitalized }
    }

    /// Result of parsing an OAuth callback URL.
    struct CallbackResult: Equatable {
        let provider: String
        let status: String
        var isConnected: Bool { status == "connected" }
    }

    var rows: [Row] = []
    var errorMessage: String?
    var statusMessage: String?
    var isLoading = false
    /// The provider whose connect/disconnect is currently in flight, if any.
    var inFlightProvider: String?

    private let backend: IntegrationsBackend
    private let session: SessionStore
    /// Opens `authorizeUrl` in a web auth session and resolves with the callback
    /// URL (or throws on cancel/error).
    private let authorize: @MainActor (URL) async throws -> URL

    init(
        backend: IntegrationsBackend,
        session: SessionStore,
        authorize: @escaping @MainActor (URL) async throws -> URL
    ) {
        self.backend = backend
        self.session = session
        self.authorize = authorize
    }

    // MARK: - Listing

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let integrations = try await session.withAuthRetry { [backend] in
                try await backend.listIntegrations()
            }
            rows = integrations
                .map { Row(provider: $0.provider, connected: $0.connected) }
                .sorted { $0.provider < $1.provider }
        } catch {
            errorMessage = SessionStore.message(for: error)
        }
    }

    // MARK: - Connect

    /// Connect a provider: fetch the authorize URL, open the web session, then
    /// reconcile via the callback URL and refresh the list.
    func connect(provider: String) async {
        inFlightProvider = provider
        errorMessage = nil
        statusMessage = nil
        defer { inFlightProvider = nil }
        do {
            let connectResponse = try await session.withAuthRetry { [backend] in
                try await backend.connect(provider: provider)
            }
            guard let url = URL(string: connectResponse.authorizeUrl) else {
                errorMessage = "The provider returned an invalid authorization URL."
                return
            }
            let callback = try await authorize(url)
            await handleCallback(url: callback)
        } catch let error as ASWebAuthError where error == .canceled {
            statusMessage = "Connection cancelled."
        } catch {
            errorMessage = Self.connectMessage(for: error, provider: provider)
        }
    }

    // MARK: - Callback

    /// Parse a `notova://oauth/<provider>?status=connected` URL.
    nonisolated static func parseCallback(_ url: URL) -> CallbackResult? {
        guard url.scheme == "notova" else { return nil }
        // Accept both notova://oauth/<provider> (host=oauth) and the path form.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathParts = (components?.path ?? "")
            .split(separator: "/")
            .map(String.init)
        let host = components?.host

        let provider: String?
        if host == "oauth" {
            provider = pathParts.first
        } else if host != nil, pathParts.isEmpty {
            // notova://<provider>  (rare fallback)
            provider = host
        } else {
            provider = nil
        }
        guard let provider, !provider.isEmpty else { return nil }

        let status = components?.queryItems?.first { $0.name == "status" }?.value ?? "connected"
        return CallbackResult(provider: provider, status: status)
    }

    /// Apply an incoming callback URL: refresh the list on a connected result,
    /// surface a clear message otherwise. Safe to call from `onOpenURL`.
    func handleCallback(url: URL) async {
        guard let result = Self.parseCallback(url) else {
            errorMessage = "Received an unexpected callback from the provider."
            return
        }
        if result.isConnected {
            statusMessage = "Connected \(result.provider.capitalized)."
            await refresh()
        } else {
            errorMessage = "\(result.provider.capitalized) did not finish connecting (\(result.status))."
        }
    }

    // MARK: - Disconnect

    func disconnect(provider: String) async {
        inFlightProvider = provider
        errorMessage = nil
        statusMessage = nil
        defer { inFlightProvider = nil }
        do {
            _ = try await session.withAuthRetry { [backend] in
                try await backend.disconnect(provider: provider)
            }
            statusMessage = "Disconnected \(provider.capitalized)."
            await refresh()
        } catch {
            errorMessage = SessionStore.message(for: error)
        }
    }

    // MARK: - Error formatting

    /// Connect errors get extra handling for the dev-safe "provider not
    /// configured" backend error (HTTP 501 / 400 with that code).
    static func connectMessage(for error: Error, provider: String) -> String {
        if case let NotovaBackendClient.BackendError.http(status) = error, status == 501 {
            return "\(provider.capitalized) isn't configured on the server yet. Add its OAuth credentials to enable it."
        }
        return SessionStore.message(for: error)
    }
}

/// A small typed error so the view model can distinguish a user-cancelled web
/// session from a real failure without importing AuthenticationServices.
enum ASWebAuthError: Error, Equatable {
    case canceled
    case presentationFailed
}

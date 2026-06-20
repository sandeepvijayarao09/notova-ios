import Foundation
import NotovaCore
import Integrations

/// App-layer seams over `NotovaBackendClient`. They expose exactly the routes
/// the auth / integrations / export view models use, so those view models can be
/// unit-tested against an in-memory fake while production wires the real actor.
///
/// `NotovaBackendClient` (an `actor`) conforms to each below, so the same
/// concrete client satisfies all three.

/// Auth + token routes used by `AuthViewModel`.
protocol AuthBackend: Sendable {
    func setAuthToken(_ token: String?) async
    func login(email: String, password: String) async throws -> NotovaBackendClient.AuthResponse
    func register(email: String, password: String) async throws -> NotovaBackendClient.AuthResponse
    func refresh(refreshToken: String) async throws -> NotovaBackendClient.RefreshResponse
    func me() async throws -> NotovaBackendClient.User
}

/// Integration listing / connect / disconnect routes used by `IntegrationsViewModel`.
protocol IntegrationsBackend: Sendable {
    func listIntegrations() async throws -> [NotovaBackendClient.Integration]
    func connect(provider: String) async throws -> NotovaBackendClient.ConnectResponse
    func disconnect(provider: String) async throws -> NotovaBackendClient.DisconnectResponse
}

/// The single export route used by `ExportViewModel`.
protocol ExportBackend: Sendable {
    func listIntegrations() async throws -> [NotovaBackendClient.Integration]
    func export(
        provider: String,
        recording: Recording,
        summary: Summary,
        transcript: Transcript
    ) async throws -> NotovaBackendClient.ExportResponse
}

// The real client already implements every method above; the conformances are
// witness-only and add no behavior.
extension NotovaBackendClient: AuthBackend {}
extension NotovaBackendClient: IntegrationsBackend {}
extension NotovaBackendClient: ExportBackend {}

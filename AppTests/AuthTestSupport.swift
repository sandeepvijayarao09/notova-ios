import Foundation
import NotovaCore
import Integrations
import Keychain
@testable import Notova

// MARK: - DTO builders

/// The backend DTOs only synthesize a private `Decodable` init, so cross-module
/// tests construct them by decoding JSON. These helpers keep the call sites
/// readable.
enum BackendDTO {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        // Force-unwraps are acceptable in test fixtures: a bad literal is a
        // programmer error surfaced immediately by a crash in the failing test.
        // swiftlint:disable:next force_try
        try! decoder.decode(T.self, from: Data(json.utf8))
    }

    static func user(id: String = "u_1", email: String = "user@notova.app") -> NotovaBackendClient.User {
        decode(NotovaBackendClient.User.self,
               #"{"id":"\#(id)","email":"\#(email)","createdAt":"1970-01-01T00:00:00Z"}"#)
    }

    static func auth(
        email: String = "user@notova.app",
        accessToken: String = "access-1",
        refreshToken: String = "refresh-1"
    ) -> NotovaBackendClient.AuthResponse {
        decode(NotovaBackendClient.AuthResponse.self, #"""
        {"user":{"id":"u_1","email":"\#(email)","createdAt":"1970-01-01T00:00:00Z"},
         "accessToken":"\#(accessToken)","refreshToken":"\#(refreshToken)"}
        """#)
    }

    static func refresh(accessToken: String = "access-2") -> NotovaBackendClient.RefreshResponse {
        decode(NotovaBackendClient.RefreshResponse.self, #"{"accessToken":"\#(accessToken)"}"#)
    }

    static func integration(_ provider: String, connected: Bool) -> NotovaBackendClient.Integration {
        decode(NotovaBackendClient.Integration.self,
               #"{"provider":"\#(provider)","connected":\#(connected)}"#)
    }

    static func integrations(_ pairs: [(String, Bool)]) -> [NotovaBackendClient.Integration] {
        pairs.map { integration($0.0, connected: $0.1) }
    }

    static func connect(
        authorizeUrl: String = "https://provider.example/oauth?x=1",
        state: String = "st-1"
    ) -> NotovaBackendClient.ConnectResponse {
        decode(NotovaBackendClient.ConnectResponse.self,
               #"{"authorizeUrl":"\#(authorizeUrl)","state":"\#(state)"}"#)
    }

    static func disconnect(_ value: Bool = true) -> NotovaBackendClient.DisconnectResponse {
        decode(NotovaBackendClient.DisconnectResponse.self, #"{"disconnected":\#(value)}"#)
    }

    static func export(
        externalId: String = "ext-1",
        url: String? = "https://provider.example/page",
        status: String = "exported"
    ) -> NotovaBackendClient.ExportResponse {
        let urlField = url.map { "\"\($0)\"" } ?? "null"
        return decode(NotovaBackendClient.ExportResponse.self,
                      #"{"externalId":"\#(externalId)","url":\#(urlField),"status":"\#(status)"}"#)
    }
}

// MARK: - Fake backend

/// An in-memory fake satisfying every app-layer backend seam. Each route can be
/// scripted with a canned result or a thrown error, and calls are recorded so
/// tests can assert what was sent. No network ever happens.
actor FakeBackend: AuthBackend, IntegrationsBackend, ExportBackend {

    // Scripted outcomes (default to success).
    var loginResult: Result<NotovaBackendClient.AuthResponse, Error>
    var registerResult: Result<NotovaBackendClient.AuthResponse, Error>
    var refreshResult: Result<NotovaBackendClient.RefreshResponse, Error>
    var meResult: Result<NotovaBackendClient.User, Error>
    var listResult: Result<[NotovaBackendClient.Integration], Error>
    var connectResult: Result<NotovaBackendClient.ConnectResponse, Error>
    var disconnectResult: Result<NotovaBackendClient.DisconnectResponse, Error>
    var exportResult: Result<NotovaBackendClient.ExportResponse, Error>

    // Recorded interactions.
    private(set) var tokenHistory: [String?] = []
    private(set) var loginCalls: [(email: String, password: String)] = []
    private(set) var registerCalls: [(email: String, password: String)] = []
    private(set) var refreshCalls: [String] = []
    private(set) var meCallCount = 0
    private(set) var listCallCount = 0
    private(set) var connectCalls: [String] = []
    private(set) var disconnectCalls: [String] = []
    private(set) var exportCalls: [(provider: String, recordingId: UUID)] = []

    /// When > 0, the next N authorized list/connect/disconnect/export/me calls
    /// throw `.unauthorized` before succeeding — used to exercise 401 retry.
    var failAuthorizedTimes = 0

    init(
        email: String = "user@notova.app",
        accessToken: String = "access-1",
        refreshToken: String = "refresh-1"
    ) {
        let auth = BackendDTO.auth(email: email, accessToken: accessToken, refreshToken: refreshToken)
        self.loginResult = .success(auth)
        self.registerResult = .success(auth)
        self.refreshResult = .success(BackendDTO.refresh())
        self.meResult = .success(BackendDTO.user(email: email))
        self.listResult = .success([])
        self.connectResult = .success(BackendDTO.connect())
        self.disconnectResult = .success(BackendDTO.disconnect())
        self.exportResult = .success(BackendDTO.export())
    }

    // Configuration helpers (callable from synchronous test setup via await).
    func setLogin(_ result: Result<NotovaBackendClient.AuthResponse, Error>) { loginResult = result }
    func setRegister(_ result: Result<NotovaBackendClient.AuthResponse, Error>) { registerResult = result }
    func setRefresh(_ result: Result<NotovaBackendClient.RefreshResponse, Error>) { refreshResult = result }
    func setMe(_ result: Result<NotovaBackendClient.User, Error>) { meResult = result }
    func setList(_ result: Result<[NotovaBackendClient.Integration], Error>) { listResult = result }
    func setConnect(_ result: Result<NotovaBackendClient.ConnectResponse, Error>) { connectResult = result }
    func setDisconnect(_ result: Result<NotovaBackendClient.DisconnectResponse, Error>) { disconnectResult = result }
    func setExport(_ result: Result<NotovaBackendClient.ExportResponse, Error>) { exportResult = result }
    func setFailAuthorizedTimes(_ count: Int) { failAuthorizedTimes = count }

    var lastToken: String? { tokenHistory.last ?? nil }

    // MARK: AuthBackend

    func setAuthToken(_ token: String?) async { tokenHistory.append(token) }

    func login(email: String, password: String) async throws -> NotovaBackendClient.AuthResponse {
        loginCalls.append((email, password))
        return try loginResult.get()
    }

    func register(email: String, password: String) async throws -> NotovaBackendClient.AuthResponse {
        registerCalls.append((email, password))
        return try registerResult.get()
    }

    func refresh(refreshToken: String) async throws -> NotovaBackendClient.RefreshResponse {
        refreshCalls.append(refreshToken)
        return try refreshResult.get()
    }

    func me() async throws -> NotovaBackendClient.User {
        meCallCount += 1
        try throwIfAuthorizedFailureQueued()
        return try meResult.get()
    }

    // MARK: IntegrationsBackend

    func listIntegrations() async throws -> [NotovaBackendClient.Integration] {
        listCallCount += 1
        try throwIfAuthorizedFailureQueued()
        return try listResult.get()
    }

    func connect(provider: String) async throws -> NotovaBackendClient.ConnectResponse {
        connectCalls.append(provider)
        try throwIfAuthorizedFailureQueued()
        return try connectResult.get()
    }

    func disconnect(provider: String) async throws -> NotovaBackendClient.DisconnectResponse {
        disconnectCalls.append(provider)
        try throwIfAuthorizedFailureQueued()
        return try disconnectResult.get()
    }

    // MARK: ExportBackend

    func export(
        provider: String,
        recording: Recording,
        summary: Summary,
        transcript: Transcript
    ) async throws -> NotovaBackendClient.ExportResponse {
        exportCalls.append((provider, recording.id))
        try throwIfAuthorizedFailureQueued()
        return try exportResult.get()
    }

    private func throwIfAuthorizedFailureQueued() throws {
        if failAuthorizedTimes > 0 {
            failAuthorizedTimes -= 1
            throw NotovaBackendClient.BackendError.unauthorized
        }
    }
}

// MARK: - Concurrency-safe counter

/// A `Sendable` counter for use inside `@Sendable` retry closures (a captured
/// `var` would race under Swift 6 concurrency checking).
actor Counter {
    private(set) var value = 0
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

// MARK: - Test context

/// Bundles the collaborators a view-model test needs, so helper factories can
/// return a single value (and stay under SwiftLint's 2-member tuple limit).
@MainActor
struct AuthTestContext {
    let session: SessionStore
    let store: InMemoryTokenStore
    let backend: FakeBackend
}

// MARK: - Shared fixtures

enum AuthFixtures {
    static func note(withContent: Bool = true) -> Note {
        let recording = Recording(title: "Export me", durationSec: 12, source: .mic, status: .ready)
        guard withContent else { return Note(recording: recording) }
        let transcript = Transcript(recordingId: recording.id, language: "en",
                                    fullText: "Hello.", segments: [])
        let summary = Summary(recordingId: recording.id, style: "concise",
                              contentMarkdown: "## Recap", actionItems: [], model: "stub")
        return Note(recording: recording, transcript: transcript, summary: summary)
    }
}

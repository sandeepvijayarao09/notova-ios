import Foundation
import NotovaCore

/// Thin client for the Notova backend `/v1` REST contract. The backend handles
/// ONLY accounts, OAuth brokering, integration export, metadata sync, and
/// billing — never AI compute. AI (transcription / summarization) is on-device.
///
/// Design notes:
/// - `sync` transmits ONLY recording metadata (no audio, transcript, or summary).
/// - `export` is the one route that forwards transcript + summary, by design,
///   so a connected provider (Notion, Slack, …) can receive the note content.
public actor NotovaBackendClient {

    // MARK: - Domain DTOs (backend wire shapes)

    /// Backend `user` object: `{id, email, createdAt}`.
    public struct User: Codable, Sendable, Equatable {
        public let id: String
        public let email: String
        public let createdAt: Date
    }

    /// Backend `recording` object. Field names + units match the contract
    /// exactly (durationSec is seconds; source/status are the raw enum values).
    public struct RecordingDTO: Codable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let createdAt: Date
        public let durationSec: Double
        public let source: String
        public let status: String

        public init(id: String, title: String, createdAt: Date,
                    durationSec: Double, source: String, status: String) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.durationSec = durationSec
            self.source = source
            self.status = status
        }

        /// Maps an on-device `Recording` to the backend wire shape.
        public init(recording: Recording) {
            self.id = recording.id.uuidString
            self.title = recording.title
            self.createdAt = recording.createdAt
            self.durationSec = recording.durationSec
            self.source = recording.source.rawValue
            self.status = recording.status.rawValue
        }
    }

    /// Backend `summary.actionItems[]` object.
    public struct ActionItemDTO: Codable, Sendable, Equatable {
        public let id: String?
        public let text: String
        public let done: Bool
        public let dueAt: Date?

        public init(id: String? = nil, text: String, done: Bool, dueAt: Date? = nil) {
            self.id = id
            self.text = text
            self.done = done
            self.dueAt = dueAt
        }
    }

    /// Backend `summary` object. `text` carries the on-device summary markdown.
    public struct SummaryDTO: Codable, Sendable, Equatable {
        public let text: String
        public let bullets: [String]?
        public let actionItems: [ActionItemDTO]?

        public init(text: String, bullets: [String]? = nil, actionItems: [ActionItemDTO]? = nil) {
            self.text = text
            self.bullets = bullets
            self.actionItems = actionItems
        }

        /// Maps an on-device `Summary`. `text` <- `contentMarkdown`; action items
        /// carry id (uuid string), text, done. The on-device model has no dueAt.
        public init(summary: Summary) {
            self.text = summary.contentMarkdown
            self.bullets = nil
            self.actionItems = summary.actionItems.map {
                ActionItemDTO(id: $0.id.uuidString, text: $0.text, done: $0.done, dueAt: nil)
            }
        }
    }

    /// Backend `transcript.segments[]` object. Times are SECONDS.
    public struct SegmentDTO: Codable, Sendable, Equatable {
        public let startSec: Double?
        public let endSec: Double?
        public let speaker: String?
        public let text: String

        public init(startSec: Double? = nil, endSec: Double? = nil,
                    speaker: String? = nil, text: String) {
            self.startSec = startSec
            self.endSec = endSec
            self.speaker = speaker
            self.text = text
        }
    }

    /// Backend `transcript` object. `text` carries the on-device full text;
    /// segment times are SECONDS (on-device stores milliseconds).
    public struct TranscriptDTO: Codable, Sendable, Equatable {
        public let text: String
        public let segments: [SegmentDTO]?
        public let language: String?

        public init(text: String, segments: [SegmentDTO]? = nil, language: String? = nil) {
            self.text = text
            self.segments = segments
            self.language = language
        }

        /// Maps an on-device `Transcript`. `text` <- `fullText`; ms -> sec for
        /// every segment (startSec = startMs / 1000); language carried through.
        public init(transcript: Transcript) {
            self.text = transcript.fullText
            self.language = transcript.language
            self.segments = transcript.segments.map {
                SegmentDTO(
                    startSec: Double($0.startMs) / 1000.0,
                    endSec: Double($0.endMs) / 1000.0,
                    speaker: $0.speaker,
                    text: $0.text
                )
            }
        }
    }

    // MARK: - Request / Response payloads

    public struct AuthResponse: Codable, Sendable, Equatable {
        public let user: User
        public let accessToken: String
        public let refreshToken: String
    }

    public struct RefreshResponse: Codable, Sendable, Equatable {
        public let accessToken: String
    }

    public struct MeResponse: Codable, Sendable, Equatable {
        public let user: User
    }

    public struct Integration: Codable, Sendable, Equatable {
        public let provider: String
        public let connected: Bool
    }

    public struct ConnectResponse: Codable, Sendable, Equatable {
        public let authorizeUrl: String
        public let state: String
    }

    public enum ExportStatus: String, Codable, Sendable {
        case exported
        case queued
        case skipped
    }

    public struct ExportResponse: Codable, Sendable, Equatable {
        public let externalId: String
        public let url: String?
        public let status: ExportStatus
    }

    public struct DisconnectResponse: Codable, Sendable, Equatable {
        public let disconnected: Bool
    }

    public struct SyncAckResponse: Codable, Sendable, Equatable {
        public let ok: Bool
    }

    public enum SubscriptionTier: String, Codable, Sendable {
        case free
        case pro
    }

    public struct Subscription: Codable, Sendable, Equatable {
        public let tier: SubscriptionTier
        public let renewsAt: Date?
    }

    public struct CheckoutResponse: Codable, Sendable, Equatable {
        public let checkoutUrl: String
    }

    public enum CheckoutPlan: String, Codable, Sendable {
        case proMonthly = "pro_monthly"
        case proYearly = "pro_yearly"
        case pro
    }

    /// One `error` detail: `{ code, message, details? }`.
    public struct ErrorDetail: Codable, Sendable, Equatable {
        public let code: String
        public let message: String
    }

    /// Decoded backend error envelope: `{ "error": { code, message, details? } }`.
    public struct ErrorBody: Codable, Sendable, Equatable {
        public let error: ErrorDetail
    }

    public enum BackendError: Error, Sendable {
        case http(Int)
        case decoding(String)
        case unauthorized
    }

    // MARK: - State

    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?

    public init(baseURL: URL = URL(string: "https://api.notova.app")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Auth (no bearer for register/login/refresh)

    /// POST /v1/auth/register
    public func register(email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let email: String; let password: String }
        return try await request(
            method: "POST", path: "/v1/auth/register",
            body: Body(email: email, password: password),
            authorized: false, as: AuthResponse.self
        )
    }

    /// POST /v1/auth/login
    public func login(email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let email: String; let password: String }
        return try await request(
            method: "POST", path: "/v1/auth/login",
            body: Body(email: email, password: password),
            authorized: false, as: AuthResponse.self
        )
    }

    /// POST /v1/auth/refresh
    public func refresh(refreshToken: String) async throws -> RefreshResponse {
        struct Body: Encodable { let refreshToken: String }
        return try await request(
            method: "POST", path: "/v1/auth/refresh",
            body: Body(refreshToken: refreshToken),
            authorized: false, as: RefreshResponse.self
        )
    }

    /// GET /v1/auth/me  (Bearer)
    public func me() async throws -> User {
        try await request(method: "GET", path: "/v1/auth/me",
                          body: EmptyBody.none, authorized: true, as: MeResponse.self).user
    }

    // MARK: - Integrations (Bearer)

    /// GET /v1/integrations
    public func listIntegrations() async throws -> [Integration] {
        try await request(method: "GET", path: "/v1/integrations",
                          body: EmptyBody.none, authorized: true, as: [Integration].self)
    }

    /// GET /v1/integrations/{provider}/connect
    public func connect(provider: String) async throws -> ConnectResponse {
        try await request(method: "GET", path: "/v1/integrations/\(provider)/connect",
                          body: EmptyBody.none, authorized: true, as: ConnectResponse.self)
    }

    /// POST /v1/integrations/{provider}/export
    ///
    /// This is the only route that forwards transcript + summary content (by
    /// design) so the provider can persist the note. Accepts on-device models
    /// and maps them to the backend DTOs.
    public func export(
        provider: String,
        recording: Recording,
        summary: Summary,
        transcript: Transcript
    ) async throws -> ExportResponse {
        struct Body: Encodable {
            let recording: RecordingDTO
            let summary: SummaryDTO
            let transcript: TranscriptDTO
        }
        let body = Body(
            recording: RecordingDTO(recording: recording),
            summary: SummaryDTO(summary: summary),
            transcript: TranscriptDTO(transcript: transcript)
        )
        return try await request(
            method: "POST", path: "/v1/integrations/\(provider)/export",
            body: body, authorized: true, as: ExportResponse.self
        )
    }

    /// DELETE /v1/integrations/{provider}
    public func disconnect(provider: String) async throws -> DisconnectResponse {
        try await request(method: "DELETE", path: "/v1/integrations/\(provider)",
                          body: EmptyBody.none, authorized: true, as: DisconnectResponse.self)
    }

    // MARK: - Sync (Bearer) — metadata only, never audio/transcript/summary

    /// GET /v1/sync/recordings?since=ISO
    public func fetchRecordings(since: Date? = nil) async throws -> [RecordingDTO] {
        var path = "/v1/sync/recordings"
        if let since {
            let formatter = ISO8601DateFormatter()
            let value = formatter.string(from: since)
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "since", value: value)]
            path += "?\(components.percentEncodedQuery ?? "since=\(value)")"
        }
        return try await request(method: "GET", path: path,
                                 body: EmptyBody.none, authorized: true, as: [RecordingDTO].self)
    }

    /// PUT /v1/sync/recordings/{id} — body carries metadata only (NO id; the id
    /// is in the path). Audio, transcript, and summary are intentionally absent.
    public func syncRecording(_ recording: Recording) async throws -> SyncAckResponse {
        struct Body: Encodable {
            let title: String
            let createdAt: Date
            let durationSec: Double
            let source: String
            let status: String
        }
        let body = Body(
            title: recording.title,
            createdAt: recording.createdAt,
            durationSec: recording.durationSec,
            source: recording.source.rawValue,
            status: recording.status.rawValue
        )
        return try await request(
            method: "PUT", path: "/v1/sync/recordings/\(recording.id.uuidString)",
            body: body, authorized: true, as: SyncAckResponse.self
        )
    }

    // MARK: - Billing (Bearer)

    /// GET /v1/billing/subscription
    public func subscription() async throws -> Subscription {
        try await request(method: "GET", path: "/v1/billing/subscription",
                          body: EmptyBody.none, authorized: true, as: Subscription.self)
    }

    /// POST /v1/billing/checkout
    public func checkout(plan: CheckoutPlan) async throws -> CheckoutResponse {
        struct Body: Encodable { let plan: CheckoutPlan }
        return try await request(
            method: "POST", path: "/v1/billing/checkout",
            body: Body(plan: plan), authorized: true, as: CheckoutResponse.self
        )
    }

    // MARK: - Transport

    /// Sentinel for "no request body" so generic `body:` calls stay typed.
    private enum EmptyBody: Encodable {
        case none
        func encode(to encoder: Encoder) throws {}
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func request<Body: Encodable, T: Decodable>(
        method: String,
        path: String,
        body: Body?,
        authorized: Bool,
        as type: T.Type
    ) async throws -> T {
        let data = try await send(method: method, path: path, body: body, authorized: authorized)
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    @discardableResult
    private func send<Body: Encodable>(
        method: String,
        path: String,
        body: Body?,
        authorized: Bool
    ) async throws -> Data {
        // `appendingPathComponent` would percent-encode the "?" in query strings,
        // so resolve the path (incl. any query) relative to the base URL instead.
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BackendError.decoding("invalid URL for path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let body, !(body is EmptyBody) {
            request.httpBody = try Self.makeEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.http(-1)
        }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw BackendError.unauthorized
        default: throw BackendError.http(http.statusCode)
        }
    }
}

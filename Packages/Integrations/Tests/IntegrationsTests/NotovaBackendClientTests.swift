import XCTest
import NotovaCore
@testable import Integrations

/// Tests the request construction + typed-response decoding for every
/// `NotovaBackendClient` endpoint. Error handling lives in
/// `NotovaBackendErrorTests`; pure DTO mapping in `NotovaBackendDTOMappingTests`.
/// Shared fixtures + the `makeClient` factory live in `NotovaBackendTestSupport`.
final class NotovaBackendClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubState.shared.reset()
    }

    override func tearDown() {
        StubState.shared.reset()
        super.tearDown()
    }

    private func makeClient(token: String? = nil) async -> NotovaBackendClient {
        await makeBackendClient(token: token)
    }

    // MARK: - POST /v1/auth/register

    func testRegisterRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"""
            {"user":{"id":"u_1","email":"a@b.com","createdAt":"2026-06-19T03:00:00Z"},
             "accessToken":"acc","refreshToken":"ref"}
            """#)
        }
        let client = await makeClient()
        let result = try await client.register(email: "a@b.com", password: "pw")

        XCTAssertEqual(result.accessToken, "acc")
        XCTAssertEqual(result.refreshToken, "ref")
        XCTAssertEqual(result.user.id, "u_1")
        XCTAssertEqual(result.user.email, "a@b.com")

        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url?.path, "/v1/auth/register")
        XCTAssertNil(req.headers["Authorization"], "register must NOT send a bearer token")
        let body = try XCTUnwrap(req.bodyJSON)
        XCTAssertEqual(body["email"] as? String, "a@b.com")
        XCTAssertEqual(body["password"] as? String, "pw")
    }

    func testRegisterDoesNotSendBearerEvenWhenTokenSet() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"user":{"id":"u","email":"e","createdAt":"2026-06-19T03:00:00Z"},"accessToken":"a","refreshToken":"r"}"#)
        }
        let client = await makeClient(token: "stale-token")
        _ = try await client.register(email: "e", password: "p")
        XCTAssertNil(StubState.shared.lastRequest?.headers["Authorization"])
    }

    // MARK: - POST /v1/auth/login

    func testLoginRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"user":{"id":"u_9","email":"x@y.com","createdAt":"2026-06-19T03:00:00Z"},"accessToken":"AT","refreshToken":"RT"}"#)
        }
        let client = await makeClient()
        let result = try await client.login(email: "x@y.com", password: "secret")

        XCTAssertEqual(result.accessToken, "AT")
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url?.path, "/v1/auth/login")
        XCTAssertNil(req.headers["Authorization"], "login must NOT send a bearer token")
        let body = try XCTUnwrap(req.bodyJSON)
        XCTAssertEqual(body["email"] as? String, "x@y.com")
        XCTAssertEqual(body["password"] as? String, "secret")
    }

    // MARK: - POST /v1/auth/refresh

    func testRefreshRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in .json(#"{"accessToken":"new-access"}"#) }
        let client = await makeClient()
        let result = try await client.refresh(refreshToken: "the-refresh")

        XCTAssertEqual(result.accessToken, "new-access")
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url?.path, "/v1/auth/refresh")
        XCTAssertNil(req.headers["Authorization"], "refresh must NOT send a bearer token")
        let body = try XCTUnwrap(req.bodyJSON)
        XCTAssertEqual(body["refreshToken"] as? String, "the-refresh")
    }

    // MARK: - GET /v1/auth/me (Bearer)

    func testMeRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"user":{"id":"u_me","email":"me@notova.app","createdAt":"2026-06-19T03:00:00Z"}}"#)
        }
        let client = await makeClient(token: "tok-me")
        let user = try await client.me()

        XCTAssertEqual(user.id, "u_me")
        XCTAssertEqual(user.email, "me@notova.app")
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url?.path, "/v1/auth/me")
        XCTAssertEqual(req.headers["Authorization"], "Bearer tok-me")
        XCTAssertNil(req.body, "GET must not send a body")
    }

    func testMeRequiresAuthorizationHeaderWhenTokenSet() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"user":{"id":"u","email":"e","createdAt":"2026-06-19T03:00:00Z"}}"#)
        }
        let client = await makeClient(token: "secret-token-123")
        _ = try await client.me()
        XCTAssertEqual(StubState.shared.lastRequest?.headers["Authorization"], "Bearer secret-token-123")
    }

    func testTokenCanBeCleared() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"user":{"id":"u","email":"e","createdAt":"2026-06-19T03:00:00Z"}}"#)
        }
        let client = await makeClient(token: "tok")
        await client.setAuthToken(nil)
        _ = try await client.me()
        XCTAssertNil(StubState.shared.lastRequest?.headers["Authorization"])
    }

    // MARK: - GET /v1/integrations (Bearer)

    func testListIntegrationsRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"""
            [{"provider":"google","connected":true},
             {"provider":"notion","connected":false},
             {"provider":"slack","connected":false},
             {"provider":"salesforce","connected":true}]
            """#)
        }
        let client = await makeClient(token: "t")
        let integrations = try await client.listIntegrations()

        XCTAssertEqual(integrations.count, 4)
        XCTAssertEqual(integrations[0], NotovaBackendClient.Integration(provider: "google", connected: true))
        XCTAssertEqual(integrations[1].provider, "notion")
        XCTAssertFalse(integrations[1].connected)

        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url?.path, "/v1/integrations")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
    }

    func testListIntegrationsEmpty() async throws {
        StubState.shared.setHandler { _ in .json("[]") }
        let client = await makeClient(token: "t")
        let integrations = try await client.listIntegrations()
        XCTAssertEqual(integrations, [])
    }

    // MARK: - GET /v1/integrations/{provider}/connect (Bearer)

    func testConnectRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"authorizeUrl":"https://accounts.google.com/o/oauth2?x=1","state":"st-123"}"#)
        }
        let client = await makeClient(token: "t")
        let result = try await client.connect(provider: "google")

        XCTAssertEqual(result.authorizeUrl, "https://accounts.google.com/o/oauth2?x=1")
        XCTAssertEqual(result.state, "st-123")
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url?.path, "/v1/integrations/google/connect")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
    }

    // MARK: - POST /v1/integrations/{provider}/export (Bearer)

    func testExportRequestPathMethodAndAuth() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"externalId":"ext_1","url":"https://notion.so/page","status":"exported"}"#)
        }
        let id = UUID()
        let client = await makeClient(token: "t")
        let result = try await client.export(
            provider: "notion",
            recording: sampleRecording(id: id),
            summary: sampleSummary(id: id),
            transcript: sampleTranscript(id: id)
        )

        XCTAssertEqual(result.externalId, "ext_1")
        XCTAssertEqual(result.url, "https://notion.so/page")
        XCTAssertEqual(result.status, .exported)

        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url?.path, "/v1/integrations/notion/export")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
    }

    func testExportDecodesQueuedStatusWithNullURL() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"externalId":"ext_q","url":null,"status":"queued"}"#)
        }
        let id = UUID()
        let client = await makeClient(token: "t")
        let result = try await client.export(
            provider: "slack", recording: sampleRecording(id: id),
            summary: sampleSummary(id: id), transcript: sampleTranscript(id: id))
        XCTAssertEqual(result.status, .queued)
        XCTAssertNil(result.url)
    }

    func testExportDecodesSkippedStatusWithMissingURL() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"externalId":"ext_s","status":"skipped"}"#)
        }
        let id = UUID()
        let client = await makeClient(token: "t")
        let result = try await client.export(
            provider: "slack", recording: sampleRecording(id: id),
            summary: sampleSummary(id: id), transcript: sampleTranscript(id: id))
        XCTAssertEqual(result.status, .skipped)
        XCTAssertNil(result.url)
    }

    /// Export maps the on-device recording into the backend `recording` DTO.
    func testExportMapsRecordingDTO() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"externalId":"e","status":"exported"}"#)
        }
        let id = UUID()
        let client = await makeClient(token: "t")
        try await _ = client.export(
            provider: "notion", recording: sampleRecording(id: id),
            summary: sampleSummary(id: id), transcript: sampleTranscript(id: id))

        let body = try XCTUnwrap(StubState.shared.lastRequest?.bodyJSON)
        let recording = try XCTUnwrap(body["recording"] as? [String: Any])
        XCTAssertEqual(recording["id"] as? String, id.uuidString)
        XCTAssertEqual(recording["title"] as? String, "Q2 Planning")
        XCTAssertEqual(recording["durationSec"] as? Double, 123.5)
        XCTAssertEqual(recording["source"] as? String, "bluetooth")
        XCTAssertEqual(recording["status"] as? String, "ready")
        XCTAssertNotNil(recording["createdAt"], "createdAt should be ISO date string")
        // The recording DTO must not leak the local audio path.
        XCTAssertNil(recording["localAudioPath"])
    }

    /// summary.text <- on-device contentMarkdown; action items carried through.
    func testExportMapsSummaryDTO() async throws {
        StubState.shared.setHandler { _ in .json(#"{"externalId":"e","status":"exported"}"#) }
        let id = UUID()
        let client = await makeClient(token: "t")
        try await _ = client.export(
            provider: "notion", recording: sampleRecording(id: id),
            summary: sampleSummary(id: id), transcript: sampleTranscript(id: id))

        let body = try XCTUnwrap(StubState.shared.lastRequest?.bodyJSON)
        let summary = try XCTUnwrap(body["summary"] as? [String: Any])
        XCTAssertEqual(summary["text"] as? String, "## Recap\n- Shipped v2")
        let items = try XCTUnwrap(summary["actionItems"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0]["text"] as? String, "Email the team")
        XCTAssertEqual(items[0]["done"] as? Bool, false)
        XCTAssertNotNil(items[0]["id"])
        XCTAssertEqual(items[1]["text"] as? String, "File ticket")
        XCTAssertEqual(items[1]["done"] as? Bool, true)
    }

    /// transcript.text <- fullText; ms -> sec conversion for segments; language carried.
    func testExportMapsTranscriptDTOWithMsToSec() async throws {
        StubState.shared.setHandler { _ in .json(#"{"externalId":"e","status":"exported"}"#) }
        let id = UUID()
        let client = await makeClient(token: "t")
        try await _ = client.export(
            provider: "notion", recording: sampleRecording(id: id),
            summary: sampleSummary(id: id), transcript: sampleTranscript(id: id))

        let body = try XCTUnwrap(StubState.shared.lastRequest?.bodyJSON)
        let transcript = try XCTUnwrap(body["transcript"] as? [String: Any])
        XCTAssertEqual(transcript["text"] as? String, "Hello world. Goodbye.")
        XCTAssertEqual(transcript["language"] as? String, "en")
        let segments = try XCTUnwrap(transcript["segments"] as? [[String: Any]])
        XCTAssertEqual(segments.count, 2)
        // 0ms -> 0.0s, 1500ms -> 1.5s, 3250ms -> 3.25s
        XCTAssertEqual(segments[0]["startSec"] as? Double, 0.0)
        XCTAssertEqual(segments[0]["endSec"] as? Double, 1.5)
        XCTAssertEqual(segments[0]["speaker"] as? String, "Speaker 1")
        XCTAssertEqual(segments[0]["text"] as? String, "Hello world.")
        XCTAssertEqual(segments[1]["startSec"] as? Double, 1.5)
        XCTAssertEqual(segments[1]["endSec"] as? Double, 3.25)
    }

    // MARK: - DELETE /v1/integrations/{provider} (Bearer)

    func testDisconnectRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in .json(#"{"disconnected":true}"#) }
        let client = await makeClient(token: "t")
        let result = try await client.disconnect(provider: "salesforce")

        XCTAssertTrue(result.disconnected)
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "DELETE")
        XCTAssertEqual(req.url?.path, "/v1/integrations/salesforce")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
    }

    // MARK: - GET /v1/sync/recordings (Bearer)

    func testFetchRecordingsRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"""
            [{"id":"11111111-1111-1111-1111-111111111111","title":"A",
              "createdAt":"2026-06-19T03:00:00Z","durationSec":10.0,"source":"mic","status":"ready"}]
            """#)
        }
        let client = await makeClient(token: "t")
        let recordings = try await client.fetchRecordings()

        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings[0].title, "A")
        XCTAssertEqual(recordings[0].source, "mic")
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url?.path, "/v1/sync/recordings")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
    }

    func testFetchRecordingsSendsSinceQueryParameter() async throws {
        StubState.shared.setHandler { _ in .json("[]") }
        let client = await makeClient(token: "t")
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await client.fetchRecordings(since: since)

        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.url?.path, "/v1/sync/recordings")
        let components = URLComponents(url: try XCTUnwrap(req.url), resolvingAgainstBaseURL: false)
        let sinceValue = components?.queryItems?.first { $0.name == "since" }?.value
        XCTAssertNotNil(sinceValue)
        XCTAssertTrue(try XCTUnwrap(sinceValue).contains("2023-11-14"))
    }

    // MARK: - PUT /v1/sync/recordings/{id} (Bearer) — metadata only

    func testSyncRecordingRequestConstruction() async throws {
        StubState.shared.setHandler { _ in .json(#"{"ok":true}"#) }
        let client = await makeClient(token: "t")
        let id = UUID()
        let recording = Recording(id: id, title: "Meeting", durationSec: 90, source: .mic,
                                  localAudioPath: "/private/var/audio.m4a", status: .ready)
        let ack = try await client.syncRecording(recording)

        XCTAssertTrue(ack.ok)
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "PUT")
        XCTAssertEqual(req.url?.path, "/v1/sync/recordings/\(id.uuidString)")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
        let body = try XCTUnwrap(req.bodyJSON)
        XCTAssertEqual(body["title"] as? String, "Meeting")
        XCTAssertEqual(body["durationSec"] as? Double, 90)
        XCTAssertEqual(body["source"] as? String, "mic")
        XCTAssertEqual(body["status"] as? String, "ready")
        XCTAssertNotNil(body["createdAt"])
    }

    /// Documents the contract: sync transmits ONLY metadata — never the id in
    /// the body (it's in the path), and never audio/transcript/summary content.
    /// Export, by contrast, forwards transcript + summary by design.
    func testSyncTransmitsOnlyMetadataNoAudioTranscriptOrSummary() async throws {
        StubState.shared.setHandler { _ in .json(#"{"ok":true}"#) }
        let client = await makeClient(token: "t")
        let recording = Recording(title: "Secret talk", source: .mic,
                                  localAudioPath: "/private/var/super-secret-audio.m4a")
        _ = try await client.syncRecording(recording)

        let body = try XCTUnwrap(StubState.shared.lastRequest?.bodyJSON)
        // The id lives in the PATH, never the body.
        XCTAssertNil(body["id"], "id must be in the path, not the body")
        // Metadata-only contract: never the local audio path, transcript, or summary.
        XCTAssertNil(body["localAudioPath"], "audio path must never be synced")
        XCTAssertNil(body["transcript"])
        XCTAssertNil(body["fullText"])
        XCTAssertNil(body["summary"])
        XCTAssertNil(body["contentMarkdown"])
        XCTAssertNil(body["actionItems"])
        XCTAssertNil(body["segments"])
        let raw = try XCTUnwrap(StubState.shared.lastRequest?.bodyString)
        XCTAssertFalse(raw.contains("super-secret-audio"))
        // Allowed metadata keys only (NO id).
        XCTAssertEqual(Set(body.keys), ["title", "createdAt", "durationSec", "source", "status"])
    }

    func testSyncEncodesDatesAsISO8601() async throws {
        StubState.shared.setHandler { _ in .json(#"{"ok":true}"#) }
        let client = await makeClient(token: "t")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await client.syncRecording(Recording(title: "x", createdAt: date))
        let createdAt = try XCTUnwrap(StubState.shared.lastRequest?.bodyJSON?["createdAt"] as? String)
        XCTAssertTrue(createdAt.contains("2023-11-14"), "expected ISO8601 date, got \(createdAt)")
    }

    // MARK: - GET /v1/billing/subscription (Bearer)

    func testSubscriptionRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"tier":"pro","renewsAt":"2026-12-31T00:00:00Z"}"#)
        }
        let client = await makeClient(token: "t")
        let sub = try await client.subscription()

        XCTAssertEqual(sub.tier, .pro)
        XCTAssertNotNil(sub.renewsAt)
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.url?.path, "/v1/billing/subscription")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
    }

    func testSubscriptionFreeTierWithoutRenewsAt() async throws {
        StubState.shared.setHandler { _ in .json(#"{"tier":"free"}"#) }
        let client = await makeClient(token: "t")
        let sub = try await client.subscription()
        XCTAssertEqual(sub.tier, .free)
        XCTAssertNil(sub.renewsAt)
    }

    // MARK: - POST /v1/billing/checkout (Bearer)

    func testCheckoutRequestAndDecoding() async throws {
        StubState.shared.setHandler { _ in
            .json(#"{"checkoutUrl":"https://checkout.stripe.com/pay/abc"}"#)
        }
        let client = await makeClient(token: "t")
        let result = try await client.checkout(plan: .proYearly)

        XCTAssertEqual(result.checkoutUrl, "https://checkout.stripe.com/pay/abc")
        let req = try XCTUnwrap(StubState.shared.lastRequest)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url?.path, "/v1/billing/checkout")
        XCTAssertEqual(req.headers["Authorization"], "Bearer t")
        let body = try XCTUnwrap(req.bodyJSON)
        XCTAssertEqual(body["plan"] as? String, "pro_yearly")
    }

    func testCheckoutPlanRawValues() async throws {
        StubState.shared.setHandler { _ in .json(#"{"checkoutUrl":"u"}"#) }
        let client = await makeClient(token: "t")
        _ = try await client.checkout(plan: .proMonthly)
        XCTAssertEqual(StubState.shared.lastRequest?.bodyJSON?["plan"] as? String, "pro_monthly")
        _ = try await client.checkout(plan: .pro)
        XCTAssertEqual(StubState.shared.lastRequest?.bodyJSON?["plan"] as? String, "pro")
    }

}

import XCTest
import NotovaCore
@testable import Integrations

/// Error-path coverage for `NotovaBackendClient`: status-code mapping
/// (401 -> unauthorized, others -> http(status)), malformed / wrong-shape JSON
/// decoding failures, propagation through write routes, and the backend error
/// envelope shape. Shared helpers live in `NotovaBackendTestSupport`.
final class NotovaBackendErrorTests: XCTestCase {

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

    func testUnauthorized401ThrowsUnauthorized() async {
        StubState.shared.setHandler { _ in
            .json(#"{"error":{"code":"unauthorized","message":"no"}}"#, status: 401)
        }
        let client = await makeClient(token: "t")
        await assertBackendUnauthorized { _ = try await client.me() }
    }

    func testBadRequest400ThrowsHTTP() async {
        StubState.shared.setHandler { _ in
            .json(#"{"error":{"code":"bad_request","message":"bad"}}"#, status: 400)
        }
        let client = await makeClient(token: "t")
        await assertHTTPError(code: 400) { _ = try await client.me() }
    }

    func testServerError500ThrowsHTTP() async {
        StubState.shared.setHandler { _ in
            .json(#"{"error":{"code":"server_error","message":"boom"}}"#, status: 500)
        }
        let client = await makeClient(token: "t")
        await assertHTTPError(code: 500) { _ = try await client.me() }
    }

    func testMalformedJSONThrowsDecoding() async {
        StubState.shared.setHandler { _ in .json("{not valid json", status: 200) }
        let client = await makeClient(token: "t")
        await assertDecodingError { _ = try await client.me() }
    }

    func testWrongShapeJSONThrowsDecoding() async {
        // Valid JSON but missing the required `user` for the /me response.
        StubState.shared.setHandler { _ in .json(#"{"id":"only-id"}"#, status: 200) }
        let client = await makeClient(token: "t")
        await assertDecodingError { _ = try await client.me() }
    }

    func testExportPropagatesServerError() async {
        StubState.shared.setHandler { _ in .json("{}", status: 503) }
        let client = await makeClient(token: "t")
        let id = UUID()
        await assertHTTPError(code: 503) {
            _ = try await client.export(provider: "notion", recording: self.sampleRecording(id: id),
                                        summary: self.sampleSummary(id: id),
                                        transcript: self.sampleTranscript(id: id))
        }
    }

    func testSyncPropagatesServerError() async {
        StubState.shared.setHandler { _ in .json("{}", status: 503) }
        let client = await makeClient(token: "t")
        await assertHTTPError(code: 503) {
            _ = try await client.syncRecording(Recording(title: "x"))
        }
    }

    func testErrorBodyDecodesEnvelope() throws {
        let json = Data(#"{"error":{"code":"rate_limited","message":"slow down"}}"#.utf8)
        let body = try JSONDecoder().decode(NotovaBackendClient.ErrorBody.self, from: json)
        XCTAssertEqual(body.error.code, "rate_limited")
        XCTAssertEqual(body.error.message, "slow down")
    }
}

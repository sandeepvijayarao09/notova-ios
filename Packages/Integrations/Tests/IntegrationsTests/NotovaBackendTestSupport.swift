import XCTest
import NotovaCore
@testable import Integrations

/// Shared helpers for the `NotovaBackendClient` test suites: a stubbed client
/// factory, on-device fixtures, and typed-error assertions. Kept in an
/// `XCTestCase` extension so each test class stays focused on its endpoints.
extension XCTestCase {

    static var stubBaseURL: URL { URL(string: "https://api.notova.app")! }

    func makeBackendClient(token: String? = nil) async -> NotovaBackendClient {
        let client = NotovaBackendClient(baseURL: Self.stubBaseURL, session: StubURLProtocol.makeSession())
        if let token { await client.setAuthToken(token) }
        return client
    }

    // MARK: - On-device fixtures

    func sampleRecording(id: UUID = UUID()) -> Recording {
        Recording(id: id, title: "Q2 Planning",
                  createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                  durationSec: 123.5, source: .bluetooth,
                  localAudioPath: "/private/var/secret-audio.m4a", status: .ready)
    }

    func sampleSummary(id: UUID) -> Summary {
        Summary(recordingId: id, style: "concise",
                contentMarkdown: "## Recap\n- Shipped v2",
                actionItems: [ActionItem(text: "Email the team", done: false),
                              ActionItem(text: "File ticket", done: true)],
                model: "stub")
    }

    func sampleTranscript(id: UUID) -> Transcript {
        Transcript(recordingId: id, language: "en", fullText: "Hello world. Goodbye.",
                   segments: [TranscriptSegment(startMs: 0, endMs: 1500,
                                                text: "Hello world.", speaker: "Speaker 1"),
                              TranscriptSegment(startMs: 1500, endMs: 3250,
                                                text: "Goodbye.", speaker: "Speaker 2")])
    }

    // MARK: - Error assertions

    func assertBackendUnauthorized(
        _ block: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("Expected unauthorized error", file: file, line: line)
        } catch NotovaBackendClient.BackendError.unauthorized {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func assertHTTPError(
        code: Int,
        _ block: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("Expected HTTP \(code) error", file: file, line: line)
        } catch let NotovaBackendClient.BackendError.http(status) {
            XCTAssertEqual(status, code, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func assertDecodingError(
        _ block: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("Expected decoding error", file: file, line: line)
        } catch let NotovaBackendClient.BackendError.decoding(message) {
            XCTAssertFalse(message.isEmpty, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

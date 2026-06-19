import XCTest
import NotovaCore
@testable import Transcription

final class AppleSpeechTranscriberTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/x.m4a")

    // MARK: - Fake backend

    private struct FakeBackend: SpeechRecognitionBackend {
        let available: Bool
        let result: RecognitionResult?
        let error: Error?

        init(available: Bool, result: RecognitionResult? = nil, error: Error? = nil) {
            self.available = available
            self.result = result
            self.error = error
        }

        func isAvailable() async -> Bool { available }
        func recognize(audioURL: URL) async throws -> RecognitionResult {
            if let error { throw error }
            return result ?? RecognitionResult(fullText: "", localeIdentifier: "en_US", segments: [])
        }
    }

    // MARK: - Availability gating

    func testReportsUnavailableWhenBackendUnavailable() async {
        let transcriber = AppleSpeechTranscriber(backend: FakeBackend(available: false))
        let available = await transcriber.isAvailable()
        XCTAssertFalse(available)
    }

    func testReportsAvailableWhenBackendAvailable() async {
        let transcriber = AppleSpeechTranscriber(backend: FakeBackend(available: true))
        let available = await transcriber.isAvailable()
        XCTAssertTrue(available)
    }

    func testEngineNameStable() {
        XCTAssertEqual(AppleSpeechTranscriber().engineName, "Apple Speech (on-device)")
    }

    // MARK: - Mapping

    func testMapsRecognitionResultToTranscript() async throws {
        let result = RecognitionResult(
            fullText: "Hello world. Send the report.",
            localeIdentifier: "en_US",
            segments: [
                RecognizedSegment(text: "Hello world.", startSec: 0, durationSec: 1.5),
                RecognizedSegment(text: "Send the report.", startSec: 1.5, durationSec: 2.0)
            ]
        )
        let transcriber = AppleSpeechTranscriber(backend: FakeBackend(available: true, result: result))
        let id = UUID()
        let transcript = try await transcriber.transcribe(audioURL: url, recordingId: id)

        XCTAssertEqual(transcript.recordingId, id)
        XCTAssertEqual(transcript.language, "en", "language should be derived from the locale prefix")
        XCTAssertEqual(transcript.fullText, "Hello world. Send the report.")
        XCTAssertEqual(transcript.segments.count, 2)
        XCTAssertEqual(transcript.segments[0].startMs, 0)
        XCTAssertEqual(transcript.segments[0].endMs, 1500)
        XCTAssertEqual(transcript.segments[1].startMs, 1500)
        XCTAssertEqual(transcript.segments[1].endMs, 3500)
        XCTAssertEqual(transcript.segments[1].text, "Send the report.")
    }

    func testLocaleWithDashIsTruncatedToLanguage() {
        let result = RecognitionResult(fullText: "Bonjour.", localeIdentifier: "fr-FR", segments: [])
        let transcript = AppleSpeechTranscriber.makeTranscript(from: result, recordingId: UUID())
        XCTAssertEqual(transcript.language, "fr")
    }

    func testEmptyLocaleDefaultsToEnglish() {
        let result = RecognitionResult(fullText: "x", localeIdentifier: "", segments: [])
        let transcript = AppleSpeechTranscriber.makeTranscript(from: result, recordingId: UUID())
        XCTAssertEqual(transcript.language, "en")
    }

    func testRecognitionErrorPropagates() async {
        let transcriber = AppleSpeechTranscriber(
            backend: FakeBackend(available: true, error: NotovaError.transcriptionFailed("boom"))
        )
        do {
            _ = try await transcriber.transcribe(audioURL: url, recordingId: UUID())
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NotovaError, .transcriptionFailed("boom"))
        }
    }
}

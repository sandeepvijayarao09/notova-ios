import XCTest
import NotovaCore
@testable import Transcription

final class TranscriptionServiceTests: XCTestCase {
    func testMakeDefaultReturnsAConformingTranscriber() async throws {
        let transcriber = TranscriptionService.makeDefault()
        let id = UUID()
        let transcript = try await transcriber.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a"),
            recordingId: id
        )
        XCTAssertEqual(transcript.recordingId, id)
        XCTAssertFalse(transcript.fullText.isEmpty)
        XCTAssertFalse(transcript.segments.isEmpty)
        XCTAssertEqual(transcript.language, "en")
    }

    func testMakeDefaultIsCurrentlyStub() async throws {
        // Today the default is the StubTranscriber from NotovaCore; assert the
        // deterministic 4-segment shape so a swap to Whisper is a conscious change.
        let transcript = try await TranscriptionService.makeDefault()
            .transcribe(audioURL: URL(fileURLWithPath: "/tmp/x"), recordingId: UUID())
        XCTAssertEqual(transcript.segments.count, 4)
    }
}

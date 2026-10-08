import XCTest
import NotovaCore
@testable import Transcription

final class TranscriptionServiceTests: XCTestCase {
    func testMakeDefaultIsTheResolvingTranscriber() {
        XCTAssertTrue(TranscriptionService.makeDefault() is ResolvingTranscriber)
    }

    func testDefaultChainHasNoPlaceholderEngine() {
        let names = TranscriptionService.defaultEngines().map(\.engineName)
        XCTAssertFalse(names.contains(StubTranscriber().engineName))
    }

    func testUnavailableErrorIsReadable() {
        let error = NotovaError.transcriptionUnavailable(ResolvingTranscriber.unavailableReason)
        XCTAssertTrue(error.localizedDescription.hasPrefix("Transcription unavailable:"))
        XCTAssertTrue(error.localizedDescription.contains("Speech Recognition"))
    }
}

import XCTest
import NotovaCore
@testable import AudioCapture

final class AudioRecorderTests: XCTestCase {

    private func makeRecorder() -> AudioRecorder {
        AudioRecorder(outputDirectory: FileManager.default.temporaryDirectory)
    }

    // MARK: - loadFile extension validation

    func testLoadFileRejectsUnsupportedExtension() async {
        let recorder = makeRecorder()
        let url = URL(fileURLWithPath: "/tmp/document.txt")
        do {
            _ = try await recorder.loadFile(at: url)
            XCTFail("Expected unsupportedFile error")
        } catch let error as NotovaError {
            guard case let .unsupportedFile(message) = error else {
                return XCTFail("Wrong NotovaError case: \(error)")
            }
            XCTAssertTrue(message.contains("txt"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadFileRejectsExtensionlessFile() async {
        let recorder = makeRecorder()
        do {
            _ = try await recorder.loadFile(at: URL(fileURLWithPath: "/tmp/noextension"))
            XCTFail("Expected unsupportedFile error")
        } catch let NotovaError.unsupportedFile(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadFileAcceptsSupportedExtensionsCaseInsensitive() async throws {
        let recorder = makeRecorder()
        // The file need not exist; duration falls back to 0 when AVAudioPlayer
        // can't open it. We only assert the extension gate + reported source.
        for ext in ["m4a", "MP3", "Wav", "aac", "caf", "aiff", "aif", "mp4"] {
            let url = URL(fileURLWithPath: "/tmp/sample.\(ext)")
            let result = try await recorder.loadFile(at: url)
            XCTAssertEqual(result.source, .file)
            XCTAssertEqual(result.fileURL, url)
            XCTAssertGreaterThanOrEqual(result.durationSec, 0)
        }
    }

    func testLoadFileReportsZeroDurationForMissingFile() async throws {
        let result = try await makeRecorder().loadFile(at: URL(fileURLWithPath: "/tmp/does-not-exist.m4a"))
        XCTAssertEqual(result.durationSec, 0)
        XCTAssertEqual(result.source, .file)
    }

    // MARK: - stop() guard

    func testStopWithoutActiveRecordingThrows() async {
        let recorder = makeRecorder()
        do {
            _ = try await recorder.stop()
            XCTFail("Expected audioCaptureFailed error")
        } catch let NotovaError.audioCaptureFailed(message) {
            XCTAssertTrue(message.contains("No active recording"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - AudioCaptureResult value type

    func testAudioCaptureResultStoresFields() {
        let url = URL(fileURLWithPath: "/tmp/a.m4a")
        let result = AudioCaptureResult(fileURL: url, durationSec: 12.5, source: .bluetooth)
        XCTAssertEqual(result.fileURL, url)
        XCTAssertEqual(result.durationSec, 12.5)
        XCTAssertEqual(result.source, .bluetooth)
    }
}

final class MicrophonePermissionTests: XCTestCase {
    func testRequestReturnsBoolWithoutHanging() async {
        // On macOS (no UIKit) the helper returns true synchronously; on a
        // simulator it resolves a real continuation. Either way it must complete.
        let granted = await MicrophonePermission.request()
        XCTAssertTrue(granted == true || granted == false)
    }
}

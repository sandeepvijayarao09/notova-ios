import NotovaCore
import XCTest
@testable import NotovaMac

@MainActor
final class AppModelTests: XCTestCase {
    /// Importing a file runs the (stub) pipeline and persists a ready note.
    func testImportCreatesReadyNote() async throws {
        let model = makeModel()

        await model.importFile(at: URL(fileURLWithPath: "/tmp/meeting.m4a"))

        XCTAssertEqual(model.notes.count, 1)
        let note = try XCTUnwrap(model.notes.first)
        XCTAssertEqual(note.recording.status, .ready)
        XCTAssertEqual(note.recording.title, "meeting")
        XCTAssertNotNil(note.summary)
        XCTAssertNotNil(note.transcript)
        if case .done = model.recordState {} else { XCTFail("expected .done, got \(model.recordState)") }
    }

    /// Recording toggles into the recording state when permission is granted, then back to a
    /// finished note on stop.
    func testRecordToggleProducesNote() async {
        let model = makeModel()

        await model.toggleRecording()
        XCTAssertTrue(model.isRecording)

        await model.toggleRecording()
        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertEqual(model.notes.first?.recording.source, .mic)
    }

    /// A denied microphone permission surfaces a failure and records nothing.
    func testDeniedPermissionFails() async {
        let model = makeModel(permissionGranted: false)

        await model.startRecording()

        XCTAssertFalse(model.isRecording)
        XCTAssertTrue(model.notes.isEmpty)
        if case .failed = model.recordState {} else { XCTFail("expected .failed, got \(model.recordState)") }
    }

    func testDeleteRemovesNote() async {
        let model = makeModel()
        await model.importFile(at: URL(fileURLWithPath: "/tmp/a.m4a"))
        let note = model.notes.first!

        model.delete(note)

        XCTAssertTrue(model.notes.isEmpty)
    }

    /// Regression: Settings used to hardcode the stub engine names. The default (production) init
    /// now retains the real resolver chain, and `refreshEngineNames()` surfaces the engine that
    /// would actually run — so the names move off the "Resolving…" placeholder to a real chain
    /// entry (never nil, because the built-in engine is always the last available fallback).
    func testActiveEngineNamesComeFromResolver() async {
        let model = AppModel(
            audio: FakeAudioSource(),
            store: NoteStore(inMemory: true),
            requestPermission: { true }
        )

        XCTAssertEqual(model.activeTranscriberName, "Resolving…")
        XCTAssertEqual(model.activeSummarizerName, "Resolving…")

        await model.refreshEngineNames()

        XCTAssertNotEqual(model.activeTranscriberName, "Resolving…")
        XCTAssertNotEqual(model.activeSummarizerName, "Resolving…")
        XCTAssertFalse(model.activeTranscriberName.isEmpty)
        XCTAssertFalse(model.activeSummarizerName.isEmpty)
    }

    private func makeModel(permissionGranted: Bool = true) -> AppModel {
        AppModel(
            pipeline: PipelineService(),
            audio: FakeAudioSource(),
            store: NoteStore(inMemory: true),
            requestPermission: { permissionGranted }
        )
    }
}

/// Side-effect-free `AudioSource` for tests — never touches the microphone or filesystem.
private struct FakeAudioSource: AudioSource {
    func start() async throws {}

    func stop() async throws -> AudioCaptureResult {
        AudioCaptureResult(fileURL: URL(fileURLWithPath: "/tmp/rec.m4a"), durationSec: 3, source: .mic)
    }

    func loadFile(at url: URL) async throws -> AudioCaptureResult {
        AudioCaptureResult(fileURL: url, durationSec: 12, source: .file)
    }
}

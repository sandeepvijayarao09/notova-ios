import AISummary
import NotovaCore
import Transcription
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

    /// Regression: Settings used to hardcode the stub engine names. The resolvers passed to
    /// `AppModel` are now retained, and `refreshEngineNames()` surfaces the first *available*
    /// engine each chain would use. Injected fake engines keep this deterministic and off any real
    /// on-device availability probing (SFSpeechRecognizer / Foundation Models can block on CI).
    func testActiveEngineNamesComeFromResolver() async {
        let transcriber = ResolvingTranscriber(engines: [FakeTranscriptionEngine(name: "Fake ASR"), StubTranscriber()])
        let summarizer = ResolvingSummarizer(engines: [FakeSummarizationEngine(name: "Fake LLM"), StubSummarizer()])
        let model = AppModel(
            pipeline: PipelineService(transcriber: transcriber, summarizer: summarizer),
            transcriberResolver: transcriber,
            summarizerResolver: summarizer,
            audio: FakeAudioSource(),
            store: NoteStore(inMemory: true),
            requestPermission: { true }
        )

        XCTAssertEqual(model.activeTranscriberName, "Resolving…")
        XCTAssertEqual(model.activeSummarizerName, "Resolving…")

        await model.refreshEngineNames()

        // The first available engine in each chain surfaces (proves it reads the resolver, not a
        // hardcoded stub).
        XCTAssertEqual(model.activeTranscriberName, "Fake ASR")
        XCTAssertEqual(model.activeSummarizerName, "Fake LLM")
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

/// Always-available fake engines for the resolver test — report availability instantly (no real
/// SFSpeechRecognizer / Foundation Models probing) and are never asked to do actual work.
private struct FakeTranscriptionEngine: TranscriptionEngine {
    let name: String
    var engineName: String { name }
    func isAvailable() async -> Bool { true }
    func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        throw CancellationError()
    }
}

private struct FakeSummarizationEngine: SummarizationEngine {
    let name: String
    var engineName: String { name }
    func isAvailable() async -> Bool { true }
    func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        throw CancellationError()
    }
}

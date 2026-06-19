import XCTest
import NotovaCore
import Persistence
@testable import Notova

// MARK: - Fake audio source

/// A deterministic AudioSource for view-model tests: never touches the mic or
/// AVAudioSession. `start`/`stop` succeed and return a canned result.
private actor FakeAudioSource: AudioSource {
    enum Mode: Sendable { case succeed, failStart, failStop, failLoad }
    private let mode: Mode
    private let result: AudioCaptureResult

    init(mode: Mode = .succeed,
         result: AudioCaptureResult = AudioCaptureResult(
            fileURL: URL(fileURLWithPath: "/tmp/fake.m4a"),
            durationSec: 7,
            source: .mic)) {
        self.mode = mode
        self.result = result
    }

    func start() async throws {
        if case .failStart = mode { throw NotovaError.audioCaptureFailed("start failed") }
    }

    func stop() async throws -> AudioCaptureResult {
        if case .failStop = mode { throw NotovaError.audioCaptureFailed("stop failed") }
        return result
    }

    func loadFile(at url: URL) async throws -> AudioCaptureResult {
        if case .failLoad = mode { throw NotovaError.unsupportedFile("load failed") }
        return AudioCaptureResult(fileURL: url, durationSec: 3, source: .file)
    }
}

@MainActor
final class RecordViewModelTests: XCTestCase {

    private func makeVM(
        mode: FakeAudioSource.Mode = .succeed,
        permissionGranted: Bool = true
    ) throws -> (RecordViewModel, NoteRepository) {
        let repo = try NoteRepository(inMemory: true)
        let vm = RecordViewModel(
            audioSource: FakeAudioSource(mode: mode),
            pipeline: PipelineService(),
            repository: repo,
            requestPermission: { permissionGranted }
        )
        return (vm, repo)
    }

    func testInitialState() throws {
        let (vm, _) = try makeVM()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isRecording)
        XCTAssertEqual(vm.statusMessage, "Tap to record, or import an audio file.")
    }

    func testStartRecordingEntersRecordingState() async throws {
        let (vm, _) = try makeVM(permissionGranted: true)
        await vm.startRecording()
        XCTAssertEqual(vm.state, .recording)
        XCTAssertTrue(vm.isRecording)
    }

    func testStartRecordingDeniedPermissionSetsFailed() async throws {
        let (vm, _) = try makeVM(permissionGranted: false)
        await vm.startRecording()
        guard case .failed = vm.state else {
            return XCTFail("expected .failed when permission denied, got \(vm.state)")
        }
        XCTAssertFalse(vm.isRecording)
    }

    func testToggleStartsThenStopsAndProcesses() async throws {
        let (vm, repo) = try makeVM()
        await vm.toggleRecording()
        XCTAssertTrue(vm.isRecording)

        await vm.toggleRecording()
        // After stop + process, a note should be persisted and state == .done.
        guard case .done = vm.state else {
            return XCTFail("expected .done state, got \(vm.state)")
        }
        XCTAssertEqual(try repo.allNotes().count, 1)
        XCTAssertEqual(try repo.allNotes().first?.recording.status, .ready)
    }

    func testStopFailureSetsFailedState() async throws {
        let (vm, _) = try makeVM(mode: .failStop)
        await vm.startRecording()
        await vm.stopAndProcess()
        guard case .failed = vm.state else {
            return XCTFail("expected .failed state, got \(vm.state)")
        }
    }

    func testImportFileProcessesAndSaves() async throws {
        let (vm, repo) = try makeVM()
        await vm.importFile(at: URL(fileURLWithPath: "/tmp/imported.m4a"))
        guard case let .done(title) = vm.state else {
            return XCTFail("expected .done, got \(vm.state)")
        }
        XCTAssertEqual(title, "imported")
        let notes = try repo.allNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.recording.source, .file)
    }

    func testImportFailureSetsFailedState() async throws {
        let (vm, _) = try makeVM(mode: .failLoad)
        await vm.importFile(at: URL(fileURLWithPath: "/tmp/x.m4a"))
        guard case .failed = vm.state else {
            return XCTFail("expected .failed, got \(vm.state)")
        }
    }
}

@MainActor
final class NotesViewModelTests: XCTestCase {

    private func seededRepo(count: Int) throws -> NoteRepository {
        let repo = try NoteRepository(inMemory: true)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<count {
            let recording = Recording(title: "n\(index)", createdAt: base.addingTimeInterval(Double(index)),
                                      status: .ready)
            let summary = Summary(recordingId: recording.id, style: "s", contentMarkdown: "c",
                                  actionItems: [ActionItem(text: "do \(index)")], model: "m")
            try repo.save(Note(recording: recording, summary: summary))
        }
        return repo
    }

    func testLoadPopulatesNotesNewestFirst() throws {
        let repo = try seededRepo(count: 3)
        let vm = NotesViewModel(repository: repo)
        vm.load()
        XCTAssertEqual(vm.notes.count, 3)
        XCTAssertEqual(vm.notes.map(\.recording.title), ["n2", "n1", "n0"])
        XCTAssertNil(vm.loadError)
    }

    func testLoadEmptyRepository() throws {
        let vm = NotesViewModel(repository: try NoteRepository(inMemory: true))
        vm.load()
        XCTAssertTrue(vm.notes.isEmpty)
    }

    func testDeleteRemovesNoteAndReloads() throws {
        let repo = try seededRepo(count: 2)
        let vm = NotesViewModel(repository: repo)
        vm.load()
        let target = try XCTUnwrap(vm.notes.first)
        vm.delete(target)
        XCTAssertEqual(vm.notes.count, 1)
        XCTAssertFalse(vm.notes.contains { $0.id == target.id })
    }

    func testToggleActionItemPersistsAndReloads() throws {
        let repo = try seededRepo(count: 1)
        let vm = NotesViewModel(repository: repo)
        vm.load()
        let note = try XCTUnwrap(vm.notes.first)
        let item = try XCTUnwrap(note.summary?.actionItems.first)
        XCTAssertFalse(item.done)

        vm.toggleActionItem(in: note, item: item)

        let updated = try XCTUnwrap(vm.notes.first?.summary?.actionItems.first)
        XCTAssertTrue(updated.done, "toggling should flip done and persist")
    }

    func testToggleActionItemWithNoSummaryIsNoOp() throws {
        let repo = try NoteRepository(inMemory: true)
        let recording = Recording(title: "noSummary", status: .ready)
        try repo.save(Note(recording: recording, transcript: nil, summary: nil))
        let vm = NotesViewModel(repository: repo)
        vm.load()
        let note = try XCTUnwrap(vm.notes.first)
        // Should simply do nothing rather than crash.
        vm.toggleActionItem(in: note, item: ActionItem(text: "ghost"))
        XCTAssertNil(vm.loadError)
    }
}

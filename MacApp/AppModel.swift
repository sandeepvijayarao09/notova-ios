import AVFoundation
import Foundation
import NotovaCore
import Transcription
import AISummary
import ModelManagement

/// App-wide observable state and actions for the macOS app. Mirrors the iOS `RecordViewModel`
/// flow (record / import → on-device pipeline → save), but holds the whole-app state (sidebar
/// selection + notes list) since the Mac UI is a single window.
@MainActor
@Observable
final class AppModel {
    /// Sidebar sections.
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case record = "Record"
        case notes = "Notes"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .record: "mic"
            case .notes: "note.text"
            case .settings: "gearshape"
            }
        }
    }

    /// Lifecycle of the capture/import → process flow.
    enum RecordState: Equatable {
        case idle
        case recording
        case processing
        case done(String)
        case failed(String)
    }

    var selection: Section? = .record
    var recordState: RecordState = .idle
    var statusMessage = "Record audio or import a file — transcribed and summarized on-device."
    private(set) var notes: [Note] = []

    /// Active on-device engine names, surfaced in Settings. Populated by ``refreshEngineNames()``.
    /// Start as "Resolving…" until the (cheap) availability probe runs on launch.
    var activeTranscriberName = "Resolving…"
    var activeSummarizerName = "Resolving…"

    private let pipeline: PipelineService
    private let transcriberResolver: ResolvingTranscriber?
    private let summarizerResolver: ResolvingSummarizer?
    private let audio: any AudioSource
    private let store: NoteStore
    private let requestPermission: @Sendable () async -> Bool

    /// Designated init. When `pipeline` is omitted, the real on-device resolvers are built and
    /// retained so Settings can show which engine is actually active (Apple Speech / Foundation
    /// Models / Gemma), instead of guessing. Tests inject their own `pipeline` (resolvers stay nil).
    init(
        pipeline: PipelineService? = nil,
        transcriberResolver: ResolvingTranscriber? = nil,
        summarizerResolver: ResolvingSummarizer? = nil,
        audio: any AudioSource = MacAudioRecorder(),
        store: NoteStore = NoteStore(),
        requestPermission: @escaping @Sendable () async -> Bool = { await AppModel.requestMicPermission() }
    ) {
        if let pipeline {
            self.pipeline = pipeline
            self.transcriberResolver = transcriberResolver
            self.summarizerResolver = summarizerResolver
        } else {
            let modelStore = ModelStore()
            try? modelStore.ensureDirectory()
            let transcriber = TranscriptionService.makeResolving()
            let summarizer = SummaryService.makeResolving(store: modelStore)
            self.transcriberResolver = transcriber
            self.summarizerResolver = summarizer
            self.pipeline = PipelineService(transcriber: transcriber, summarizer: summarizer)
        }
        self.audio = audio
        self.store = store
        self.requestPermission = requestPermission
        notes = store.load()
    }

    /// Probes the on-device engine chains (no inference) and updates the Settings labels to the
    /// engine that would actually handle a request. Cheap; safe to call on launch/appear.
    func refreshEngineNames() async {
        if let transcriberResolver {
            activeTranscriberName = await transcriberResolver.previewResolution().activeEngineName ?? "None"
        }
        if let summarizerResolver {
            activeSummarizerName = await summarizerResolver.previewResolution().activeEngineName ?? "None"
        }
    }

    var isRecording: Bool { recordState == .recording }

    func toggleRecording() async {
        if isRecording {
            await stopAndProcess()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard await requestPermission() else {
            recordState = .failed("Microphone permission denied.")
            statusMessage = "Enable microphone access in System Settings ▸ Privacy & Security."
            return
        }
        do {
            try await audio.start()
            recordState = .recording
            statusMessage = "Recording… click Stop to finish."
        } catch {
            recordState = .failed(error.localizedDescription)
            statusMessage = "Could not start recording."
        }
    }

    func stopAndProcess() async {
        do {
            let result = try await audio.stop()
            await process(result: result, title: "Voice note")
        } catch {
            recordState = .failed(error.localizedDescription)
            statusMessage = "Recording failed."
        }
    }

    func importFile(at url: URL) async {
        do {
            // Security-scoped access for files picked outside the app sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let result = try await audio.loadFile(at: url)
            await process(result: result, title: url.deletingPathExtension().lastPathComponent)
        } catch {
            recordState = .failed(error.localizedDescription)
            statusMessage = "Could not import file."
        }
    }

    func delete(_ note: Note) {
        store.delete(note.id)
        notes = store.load()
    }

    private func process(result: AudioCaptureResult, title: String) async {
        recordState = .processing
        statusMessage = "Transcribing and summarizing on-device…"

        let recording = Recording(
            title: title,
            durationSec: result.durationSec,
            source: result.source,
            localAudioPath: result.fileURL.path,
            status: .processing
        )

        do {
            let note = try await pipeline.process(recording: recording, audioURL: result.fileURL)
            store.save(note)
            notes = store.load()
            recordState = .done(note.recording.title)
            statusMessage = "Saved “\(note.recording.title)”."
        } catch {
            recordState = .failed(error.localizedDescription)
            statusMessage = "Processing failed."
        }
    }

    /// Asks for microphone access via the AVFoundation TCC flow; returns the granted state.
    nonisolated private static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

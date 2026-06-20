import Foundation
import NotovaCore
import Transcription
import AISummary
import ModelManagement
import AudioCapture
import Persistence
import Integrations
import Keychain

/// Composition root. Wires concrete implementations to the protocols defined in
/// NotovaCore. The transcriber and summarizer are *resolvers* that pick the
/// first available on-device engine at call time (Apple Speech / Foundation
/// Models / local Gemma), degrading gracefully to the built-in stubs.
@Observable
@MainActor
final class AppContainer {
    let transcriber: any Transcriber
    let summarizer: any Summarizer
    /// Concrete resolver handles for surfacing the active engine in Settings.
    /// `nil` when a test injects a non-resolving fake.
    let summarizerResolver: ResolvingSummarizer?
    let transcriberResolver: ResolvingTranscriber?
    let pipeline: PipelineService
    let audioSource: any AudioSource
    let repository: NoteRepository
    let backend: NotovaBackendClient
    let exporters: [any IntegrationExporter]
    /// Manages on-device model files (import / download / delete / detect).
    let modelStore: ModelStore
    /// Secure storage for the backend access + refresh tokens.
    let tokenStore: any TokenStore
    /// Owns the authentication lifecycle (which screen the root shows + token
    /// refresh). Observed by `RootView`.
    let session: SessionStore

    /// True when launched by the UI test harness (`-uitest-seed`). Drives a
    /// deterministic, dialog-free recording path so XCUITests never block on the
    /// system microphone-permission alert.
    let isUITest: Bool

    /// Microphone-permission gate. In UI test mode this auto-grants so no system
    /// alert is shown; otherwise it defers to `MicrophonePermission`.
    let requestPermission: @Sendable () async -> Bool

    init() {
        // UI tests launch with `-uitest-seed` to get a deterministic, isolated
        // in-memory store pre-populated with one sample note, a fake audio
        // source, and an auto-granted mic permission.
        let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest-seed")
        self.isUITest = isUITest

        let modelStore = ModelStore()
        try? modelStore.ensureDirectory()
        self.modelStore = modelStore

        let summarizerResolver = SummaryService.makeResolving(store: modelStore)
        let transcriberResolver = TranscriptionService.makeResolving()
        self.summarizerResolver = summarizerResolver
        self.transcriberResolver = transcriberResolver
        self.transcriber = transcriberResolver
        self.summarizer = summarizerResolver
        self.pipeline = PipelineService(transcriber: transcriberResolver, summarizer: summarizerResolver)
        self.audioSource = isUITest ? UITestAudioSource() : AudioRecorder()
        let backend = NotovaBackendClient()
        self.backend = backend
        self.exporters = IntegrationRegistry.available()
        // UI tests run with a unique keychain service so they never collide with
        // a developer's real session, and start already "signed in" so the
        // existing tab/notes tests see the main UI without a backend.
        let tokenStore: any TokenStore = isUITest
            ? InMemoryTokenStore(tokens: AuthTokens(accessToken: "uitest", refreshToken: "uitest"))
            : KeychainTokenStore()
        self.tokenStore = tokenStore
        self.session = SessionStore(backend: backend, tokenStore: tokenStore)
        if isUITest {
            self.session.bootstrapSignedInForUITests(email: "uitest@notova.app")
        }
        let grantImmediately: @Sendable () async -> Bool = { true }
        let askSystem: @Sendable () async -> Bool = { await MicrophonePermission.request() }
        self.requestPermission = isUITest ? grantImmediately : askSystem

        do {
            self.repository = isUITest ? try NoteRepository(inMemory: true) : try NoteRepository()
        } catch {
            // Fall back to an in-memory store so the app still launches if the
            // on-disk store can't be opened.
            self.repository = (try? NoteRepository(inMemory: true)) ?? {
                fatalError("Unable to initialize NoteRepository: \(error)")
            }()
        }

        if isUITest {
            try? repository.save(Self.sampleNote())
        }
    }

    /// Test seam: inject fakes for the transcriber/summarizer (and optionally the
    /// model store / repository) without touching the production wiring.
    init(
        transcriber: any Transcriber,
        summarizer: any Summarizer,
        modelStore: ModelStore? = nil,
        repository: NoteRepository? = nil,
        exporters: [any IntegrationExporter]? = nil
    ) {
        self.isUITest = false
        self.transcriber = transcriber
        self.summarizer = summarizer
        self.summarizerResolver = summarizer as? ResolvingSummarizer
        self.transcriberResolver = transcriber as? ResolvingTranscriber
        self.pipeline = PipelineService(transcriber: transcriber, summarizer: summarizer)
        self.audioSource = UITestAudioSource()
        let backend = NotovaBackendClient()
        self.backend = backend
        self.exporters = exporters ?? IntegrationRegistry.available()
        let tokenStore = InMemoryTokenStore()
        self.tokenStore = tokenStore
        self.session = SessionStore(backend: backend, tokenStore: tokenStore)
        let store = modelStore ?? ModelStore()
        self.modelStore = store
        self.requestPermission = { true }
        self.repository = repository ?? ((try? NoteRepository(inMemory: true)) ?? {
            fatalError("Unable to initialize in-memory NoteRepository")
        }())
    }

    /// A deterministic note used to seed UI tests (never used in production).
    static func sampleNote() -> Note {
        let recording = Recording(
            title: "Sample Standup",
            durationSec: 42,
            source: .mic,
            localAudioPath: "/tmp/sample.m4a",
            status: .ready
        )
        let transcript = Transcript(
            recordingId: recording.id,
            language: "en",
            fullText: "Welcome to the sample note. Please send the recap.",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 2000,
                                  text: "Welcome to the sample note.", speaker: "Speaker 1"),
                TranscriptSegment(startMs: 2000, endMs: 4000,
                                  text: "Please send the recap.", speaker: "Speaker 1")
            ]
        )
        let summary = Summary(
            recordingId: recording.id,
            style: "concise",
            contentMarkdown: "## Summary\n- Sample note for UI tests.",
            actionItems: [ActionItem(text: "Send the recap")],
            model: StubSummarizer.modelName
        )
        return Note(recording: recording, transcript: transcript, summary: summary)
    }
}

/// A deterministic, side-effect-free `AudioSource` used only under UI tests.
/// `start`/`stop` succeed instantly without touching the microphone or
/// `AVAudioSession`, so toggling the record control is reliably observable.
private struct UITestAudioSource: AudioSource {
    func start() async throws {}

    func stop() async throws -> AudioCaptureResult {
        AudioCaptureResult(fileURL: URL(fileURLWithPath: "/tmp/uitest.m4a"), durationSec: 1, source: .mic)
    }

    func loadFile(at url: URL) async throws -> AudioCaptureResult {
        AudioCaptureResult(fileURL: url, durationSec: 1, source: .file)
    }
}

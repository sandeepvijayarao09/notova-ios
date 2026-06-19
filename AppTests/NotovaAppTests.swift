import XCTest
import NotovaCore
import ModelManagement
import Transcription
import AISummary
@testable import Notova

final class NotovaAppTests: XCTestCase {

    // MARK: - AppContainer composition root

    @MainActor
    func testContainerBuildsWithStubDependencies() {
        let container = AppContainer()
        XCTAssertEqual(container.exporters.isEmpty, false)
    }

    @MainActor
    func testContainerWiresResolvers() {
        let container = AppContainer()
        XCTAssertNotNil(container.summarizerResolver, "production wiring should use a ResolvingSummarizer")
        XCTAssertNotNil(container.transcriberResolver, "production wiring should use a ResolvingTranscriber")
        XCTAssertTrue(container.transcriber is ResolvingTranscriber)
        XCTAssertTrue(container.summarizer is ResolvingSummarizer)
    }

    @MainActor
    func testContainerExposesModelStore() {
        let container = AppContainer()
        // The models directory should be resolvable (created in init).
        XCTAssertEqual(container.modelStore.modelsDirectory.lastPathComponent, "Models")
    }

    @MainActor
    func testResolversReportEngineChain() async {
        let container = AppContainer()
        let summarizerResolution = await container.summarizerResolver?.previewResolution()
        XCTAssertEqual(summarizerResolution?.candidates.map(\.name),
                       ["Local Gemma (MLX)", "Apple Foundation Models", "Built-in sample summarizer"])
        let transcriberResolution = await container.transcriberResolver?.previewResolution()
        XCTAssertEqual(transcriberResolution?.candidates.map(\.name),
                       ["Apple Speech (on-device)", "Built-in sample transcriber"])
    }

    @MainActor
    func testTestInitInjectsFakes() async throws {
        let fakeTranscriber = FakeTranscriber()
        let fakeSummarizer = FakeSummarizer()
        let container = AppContainer(transcriber: fakeTranscriber, summarizer: fakeSummarizer)
        XCTAssertNil(container.summarizerResolver, "injected non-resolving fake exposes no resolver")
        XCTAssertNil(container.transcriberResolver)
        let note = try await container.pipeline.process(
            recording: Recording(title: "x"),
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a")
        )
        XCTAssertEqual(note.summary?.model, "fake-summarizer")
        XCTAssertEqual(note.transcript?.fullText, "fake transcript")
    }

    @MainActor
    func testContainerExportersAreNotionAndEmail() {
        let providers = AppContainer().exporters.map(\.provider)
        XCTAssertEqual(Set(providers), ["notion", "email"])
    }

    @MainActor
    func testContainerWiresPipelineWithStubs() async throws {
        let container = AppContainer()
        let note = try await container.pipeline.process(
            recording: Recording(title: "Container", source: .mic),
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a")
        )
        XCTAssertEqual(note.recording.status, .ready)
        XCTAssertNotNil(note.summary)
    }

    @MainActor
    func testSampleNoteIsConsistent() {
        let note = AppContainer.sampleNote()
        XCTAssertEqual(note.recording.title, "Sample Standup")
        XCTAssertEqual(note.recording.status, .ready)
        XCTAssertEqual(note.transcript?.recordingId, note.recording.id)
        XCTAssertEqual(note.summary?.recordingId, note.recording.id)
        XCTAssertEqual(note.summary?.actionItems.count, 1)
    }

    // MARK: - Pipeline end-to-end through the app module

    func testPipelineProducesNoteViaApp() async throws {
        let pipeline = PipelineService()
        let note = try await pipeline.process(
            recording: Recording(title: "AppTest", source: .file),
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a")
        )
        XCTAssertEqual(note.recording.status, .ready)
    }
}

// MARK: - Test doubles

private struct FakeTranscriber: Transcriber {
    func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        Transcript(recordingId: recordingId, language: "en", fullText: "fake transcript", segments: [])
    }
}

private struct FakeSummarizer: Summarizer {
    func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        Summary(recordingId: transcript.recordingId, style: style,
                contentMarkdown: "fake", actionItems: [], model: "fake-summarizer")
    }
}

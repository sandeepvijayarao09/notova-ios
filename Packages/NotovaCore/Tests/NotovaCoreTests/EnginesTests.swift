import XCTest
@testable import NotovaCore

final class EnginesTests: XCTestCase {

    // MARK: - Stub engine conformances

    func testStubTranscriberIsAlwaysAvailableEngine() async {
        let engine = StubTranscriber()
        let available = await engine.isAvailable()
        XCTAssertTrue(available)
        XCTAssertFalse(engine.engineName.isEmpty)
    }

    func testStubSummarizerIsAlwaysAvailableEngine() async {
        let engine = StubSummarizer()
        let available = await engine.isAvailable()
        XCTAssertTrue(available)
        XCTAssertFalse(engine.engineName.isEmpty)
    }

    func testStubsAreUsableThroughEngineProtocols() async throws {
        let transcriber: any TranscriptionEngine = StubTranscriber()
        let summarizer: any SummarizationEngine = StubSummarizer()
        let transcript = try await transcriber.transcribe(
            audioURL: URL(fileURLWithPath: "/tmp/x"), recordingId: UUID()
        )
        let summary = try await summarizer.summarize(transcript, style: "concise")
        XCTAssertFalse(summary.contentMarkdown.isEmpty)
    }

    // MARK: - EngineResolution

    func testEngineResolutionDefaults() {
        let resolution = EngineResolution()
        XCTAssertNil(resolution.activeEngineName)
        XCTAssertTrue(resolution.candidates.isEmpty)
    }

    func testEngineResolutionStoresCandidatesAndActive() {
        let resolution = EngineResolution(
            activeEngineName: "B",
            candidates: [.init(name: "A", available: false), .init(name: "B", available: true)]
        )
        XCTAssertEqual(resolution.activeEngineName, "B")
        XCTAssertEqual(resolution.candidates.map(\.name), ["A", "B"])
        XCTAssertEqual(resolution.candidates.first(where: \.available)?.name, "B")
    }

    func testCandidateIdIsName() {
        let candidate = EngineResolution.Candidate(name: "Engine", available: true)
        XCTAssertEqual(candidate.id, "Engine")
    }
}
